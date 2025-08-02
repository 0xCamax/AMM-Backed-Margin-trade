// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IPreInteraction} from "../interfaces/IPreInteraction.sol";
import {IOrderMixin} from "../interfaces/IOrderMixin.sol";
import {LiquidityManager} from "../contracts/LiquidityManager.sol";

contract BinaryOptionsManager is
    ReentrancyGuard,
    Ownable,
    EIP712,
    IPreInteraction
{
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    enum OptionType {
        HIGH_LOW, // Precio final >/< strike
        ONE_TOUCH, // Toca un precio objetivo una vez
        NO_TOUCH, // Nunca toca un precio objetivo
        BOUNDARY, // Dentro de un rango
        OUT_OF_BOUNDS // Fuera de un rango
    }

    struct PositionRequest {
        address user;
        address collateralToken;
        uint256 collateralAmount;
        uint256 potentialPayout;
        uint256 expiry;
        uint256 strikePrice;
        bool isCall;
        uint256 nonce;
        uint256 deadline;
        OptionType optionType;
        uint256 boundaryUpper; // Opcional
        uint256 boundaryLower; // Opcional
    }

    struct Position {
        address user;
        address collateralToken;
        uint256 collateralAmount;
        uint256 potentialPayout;
        uint256 expiry;
        uint256 strikePrice;
        bool isCall;
        OptionType optionType;
        uint256 boundaryUpper;
        uint256 boundaryLower;
        uint256 openPrice;
        bytes32 orderHash;
        PositionStatus status;
        uint256 openTimestamp;
    }

    struct OracleData {
        uint256 price;
        uint256 timestamp;
        bytes signature;
    }

    enum PositionStatus {
        Active,
        Won,
        Lost,
        Expired,
        Cancelled
    }

    bytes32 private constant POSITION_REQUEST_TYPEHASH =
        keccak256(
            "PositionRequest(address user,address collateralToken,uint256 collateralAmount,uint256 potentialPayout,uint256 expiry,uint256 strikePrice,bool isCall,uint256 nonce,uint256 deadline,uint8 optionType,uint256 boundaryUpper,uint256 boundaryLower)"
        );

    bytes32 private constant ORACLE_DATA_TYPEHASH =
        keccak256("OracleData(uint256 price,uint256 timestamp)");

    // State variables
    IOrderMixin public immutable limitOrderProtocol;
    LiquidityManager public immutable liquidityManager;
    address public appAccount; // The app's account that handles transactions

    mapping(bytes32 => Position) public positions;
    mapping(address => bytes32[]) public userPositions;
    mapping(address => uint256) public userNonces;

    uint256 public protocolFeeRate = 100; // 1% (100/10000)
    uint256 public constant MAX_FEE_RATE = 500; // 5% max

    // Minimum time before settlement (prevents manipulation)
    uint256 public minSettlementDelay = 5 minutes;

    // Events
    event PositionOpened(
        bytes32 indexed positionId,
        address indexed user,
        address collateralToken,
        uint256 collateralAmount,
        uint256 potentialPayout,
        uint256 strikePrice,
        bool isCall,
        uint256 openPrice,
        uint256 expiry
    );

    event PositionSettled(
        bytes32 indexed positionId,
        address indexed user,
        bool won,
        uint256 closePrice,
        uint256 payout
    );

    constructor(
        address _limitOrderProtocol,
        address _appAccount,
        address _liquidityManager
    ) EIP712("BinaryOptions", "1") Ownable(msg.sender) {
        limitOrderProtocol = IOrderMixin(_limitOrderProtocol);
        appAccount = _appAccount;
        liquidityManager = LiquidityManager(_liquidityManager);
    }

    modifier onlyApp() {
        require(msg.sender == appAccount, "Only app account");
        _;
    }

    modifier onlyLOP() {
        require(msg.sender == address(limitOrderProtocol), "Only LOP");
        _;
    }

    /**
     * @notice Opens a position using permit for gasless collateral transfer
     * @param request The position request details
     * @param requestSignature User's signature for the position request
     * @param permitV,permitR,permitS Permit signature for token transfer
     * @param orderHash Hash of the corresponding limit order
     * @param openPrice Current market price when opening
     */
    function openPositionWithPermit(
        PositionRequest calldata request,
        bytes calldata requestSignature,
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS,
        bytes32 orderHash,
        uint256 openPrice
    ) external onlyApp nonReentrant returns (bytes32 positionId) {
        // Verify request deadline and nonce
        require(block.timestamp <= request.deadline, "Request expired");
        require(request.nonce == userNonces[request.user], "Invalid nonce");
        require(
            request.expiry > block.timestamp + minSettlementDelay,
            "Invalid expiry"
        );

        // Verify user signature on position request
        bytes32 structHash = keccak256(
            abi.encode(
                POSITION_REQUEST_TYPEHASH,
                request.user,
                request.collateralToken,
                request.collateralAmount,
                request.potentialPayout,
                request.expiry,
                request.strikePrice,
                request.isCall,
                request.nonce,
                request.deadline,
                request.optionType,
                request.boundaryUpper,
                request.boundaryLower
            )
        );

        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(requestSignature);
        require(signer == request.user, "Invalid signature");

        // Use permit to approve token transfer
        IERC20Permit(request.collateralToken).permit(
            request.user,
            address(this),
            request.collateralAmount,
            request.deadline,
            permitV,
            permitR,
            permitS
        );

        // Transfer collateral from user
        IERC20(request.collateralToken).safeTransferFrom(
            request.user,
            address(this),
            request.collateralAmount
        );

        // Generate position ID
        positionId = keccak256(
            abi.encodePacked(
                request.user,
                orderHash,
                request.nonce,
                block.timestamp
            )
        );

        // Store position
        positions[positionId] = Position({
            user: request.user,
            collateralToken: request.collateralToken,
            collateralAmount: request.collateralAmount,
            potentialPayout: request.potentialPayout,
            expiry: request.expiry,
            strikePrice: request.strikePrice,
            isCall: request.isCall,
            optionType: request.optionType,
            boundaryUpper: request.boundaryUpper,
            boundaryLower: request.boundaryLower,
            openPrice: openPrice,
            orderHash: orderHash,
            status: PositionStatus.Active,
            openTimestamp: block.timestamp
        });

        // Track user positions and increment nonce
        userPositions[request.user].push(positionId);
        userNonces[request.user]++;

        emit PositionOpened(
            positionId,
            request.user,
            request.collateralToken,
            request.collateralAmount,
            request.potentialPayout,
            request.strikePrice,
            request.isCall,
            openPrice,
            request.expiry
        );
    }

    /**
     * @notice Settles a position using off-chain oracle data
     * @param positionId The position to settle
     * @param oracleData Signed price data from oracle
     */
    function _settlePosition(
        bytes32 positionId,
        OracleData memory oracleData
    ) internal returns (bool won) {
        Position storage position = positions[positionId];
        require(
            position.status == PositionStatus.Active,
            "Position not active"
        );
        if (block.timestamp <= position.expiry) {
            _expirePosition(positionId);
            return false;
        }
        require(
            block.timestamp >= position.openTimestamp + minSettlementDelay,
            "Settlement too early"
        );

        // Verify oracle signature
        bytes32 oracleHash = keccak256(
            abi.encode(
                ORACLE_DATA_TYPEHASH,
                oracleData.price,
                oracleData.timestamp
            )
        );
        bytes32 signedHash = _hashTypedDataV4(oracleHash);
        address oracle = signedHash.recover(oracleData.signature);
        require(oracle == appAccount, "Invalid oracle signature");

        // Verify oracle data is recent
        require(
            oracleData.timestamp >= position.openTimestamp &&
                oracleData.timestamp <= position.expiry,
            "Oracle data out of range"
        );

        // Determine if user won
        won = _checkWinCondition(position, oracleData.price);

        uint256 payout = 0;
        if (won) {
            position.status = PositionStatus.Won;
            payout = position.potentialPayout;

            liquidityManager.optionPayout(payout);

            // Transfer payout to user
            IERC20(position.collateralToken).approve(
                address(limitOrderProtocol),
                payout
            );
        } else {
            position.status = PositionStatus.Lost;
            // Collateral goes to protocol/house
            IERC20(position.collateralToken).approve(
                address(liquidityManager),
                position.collateralAmount
            );
            liquidityManager.donate(position.collateralAmount);
        }

        emit PositionSettled(
            positionId,
            position.user,
            won,
            oracleData.price,
            payout
        );
    }

    /**
     * @notice Handles expired positions - returns collateral minus processing fee
     */
    function _expirePosition(bytes32 positionId) internal {
        Position storage position = positions[positionId];
        require(
            position.status == PositionStatus.Active,
            "Position not active"
        );
        require(block.timestamp > position.expiry, "Position not expired");

        position.status = PositionStatus.Expired;

        // Return most of collateral to user
        uint256 processingFee = (position.collateralAmount * 50) / 10000; // 0.5%
        uint256 returnAmount = position.collateralAmount - processingFee;

        IERC20(position.collateralToken).safeTransfer(
            position.user,
            returnAmount
        );
        IERC20(position.collateralToken).approve(
            address(liquidityManager),
            processingFee
        );

        liquidityManager.donate(processingFee);

        emit PositionSettled(positionId, position.user, false, 0, 0);
    }

    function _checkWinCondition(
        Position memory position,
        uint256 currentPrice
    ) internal pure returns (bool) {
        if (position.optionType == OptionType.HIGH_LOW) {
            return
                position.isCall
                    ? currentPrice > position.strikePrice
                    : currentPrice < position.strikePrice;
        } else if (position.optionType == OptionType.ONE_TOUCH) {
            return
                position.isCall
                    ? currentPrice >= position.strikePrice
                    : currentPrice <= position.strikePrice;
        } else if (position.optionType == OptionType.NO_TOUCH) {
            return
                position.isCall
                    ? currentPrice < position.strikePrice
                    : currentPrice > position.strikePrice;
        } else if (position.optionType == OptionType.BOUNDARY) {
            return
                currentPrice >= position.boundaryLower &&
                currentPrice <= position.boundaryUpper;
        } else if (position.optionType == OptionType.OUT_OF_BOUNDS) {
            return
                currentPrice < position.boundaryLower ||
                currentPrice > position.boundaryUpper;
        }
        return false;
    }

    function preInteraction(
        IOrderMixin.Order calldata order,
        bytes calldata /* extension */,
        bytes32 orderHash,
        address /* taker */,
        uint256 /* makingAmount */,
        uint256 /* takingAmount */,
        uint256 /* remainingMakingAmount */,
        bytes calldata extraData
    ) external override onlyLOP {
        // Decode extraData to extract positionId and OracleData
        (bytes32 positionId, OracleData memory oracleData) = abi.decode(
            extraData,
            (bytes32, OracleData)
        );

        Position storage position = positions[positionId];

        // Sanity checks
        require(
            position.status == PositionStatus.Active,
            "Invalid position status"
        );
        require(position.orderHash == orderHash, "Order hash mismatch");
        require(
            block.timestamp >= position.openTimestamp + minSettlementDelay,
            "Too early to settle"
        );
        require(block.timestamp <= position.expiry, "Expired");

        bool won = _settlePosition(positionId, oracleData);

        if (!won) {
            limitOrderProtocol.cancelOrder(order.makerTraits, orderHash);
        }

        emit PositionSettled(
            positionId,
            position.user,
            won,
            oracleData.price,
            0
        );
    }

    // View functions
    function getUserPositions(
        address user
    ) external view returns (bytes32[] memory) {
        return userPositions[user];
    }

    function getPosition(
        bytes32 positionId
    ) external view returns (Position memory) {
        return positions[positionId];
    }

    function getUserNonce(address user) external view returns (uint256) {
        return userNonces[user];
    }

    // Admin functions
    function setAppAccount(address _appAccount) external onlyOwner {
        appAccount = _appAccount;
    }

    function setappAccount(address _appAccount) external onlyOwner {
        appAccount = _appAccount;
    }

    function setProtocolFeeRate(uint256 _feeRate) external onlyOwner {
        require(_feeRate <= MAX_FEE_RATE, "Fee rate too high");
        protocolFeeRate = _feeRate;
    }

    function setMinSettlementDelay(uint256 _delay) external onlyOwner {
        minSettlementDelay = _delay;
    }

    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
}
