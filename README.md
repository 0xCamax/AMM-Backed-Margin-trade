# AMM-Backed Margin Trading + Binary Options Protocol  

## 📖 Definition  

**An on-chain leveraged trading and binary options protocol that integrates AMMs as the source of real liquidity.**  

- Traders can open **leveraged positions** on spot assets without synthetic markets or funding rates.  
- Users can also take **binary option bets** on asset price direction within a time window.  
- LPs act as **passive margin lenders + binary options liquidity providers**, earning yield without taking directional AMM risk or impermanent loss.  

---

## 🔑 Key Components  

1. **Real AMM Liquidity**  
   - All leveraged trades and option settlements execute **1:1 against AMMs (Uniswap, Curve)**.  
   - No virtual books or synthetic pricing.  

2. **Margin Lending Pool (LPs)**  
   - LPs deposit **stablecoins** into a unified pool.  
   - Funds are used for:  
     - Leveraged traders (borrow margin)  
     - Binary options payouts (if users win)  
   - LPs earn:  
     - **Borrow interest** from traders  
     - **Losing option stakes** from binary options  
   - **No directional exposure or impermanent loss.**  

3. **Leveraged Traders**  
   - Deposit collateral + borrow margin from pool.  
   - Positions are **physically backed** in AMMs.  
   - Pay **interest** to pool and face liquidation if value < threshold.  

4. **Binary Options Users**  
   - Place a **directional bet** (UP/DOWN) on an asset with defined expiry & payout.  
   - If correct → protocol pays them from the pool.  
   - If wrong → their stake goes to the pool (LPs earn).  
   - Gasless execution via **1inch limit order protocol** for settlement.  

5. **Liquidation & Settlement Engine**  
   - For margin trades → monitors PnL and liquidates undercollateralized positions.  
   - For binary options → fetches final price from an oracle and resolves outcome, filling 1inch orders only if user wins.  

---

## 🆚 Differences from other models  

| Model                      | Liquidity            | Funding Rate | Counterparty      | LPs take directional risk |
|----------------------------|---------------------|--------------|-------------------|---------------------------|
| **Synthetic perp (dYdX)**  | Virtual             | ✅ Yes       | Traders vs traders | ❌ |
| **Perp with vault (GMX)**  | Oracle              | ✅ Yes (skew)| LP vault          | ✅ |
| **Traditional options**    | Virtual/synthetic   | ❌           | Traders vs traders | ❌ |
| **Our model**              | **Real AMM spot**   | ❌ No        | AMM spot / LP pool | ❌ |

---

## 💡 Value Proposition  

- **For traders**  
  - **Leverage on any AMM** without funding rates.  
  - **Binary options** for quick directional bets.  

- **For LPs**  
  - **Stable APY** from borrow interest + option stakes.  
  - **No IL, no delta risk.**  

- **For the protocol**  
  - Unified liquidity pool serves **both margin trading & options**, maximizing capital efficiency.  
  - **Gasless options settlement** via 1inch.  

---

## 🎯 Similarities / Differences  

- ✅ Similar to **Aave + Uniswap**, but integrated into a single margin+options layer.  
- ✅ Similar to **marginfi (Solana)** for leverage, but adds binary options.  
- ❌ Not like dYdX or GMX, since it **doesn’t create synthetic markets**, only leverages real AMM liquidity.  

---

## 📝 Elevator Pitch  

> **“A unified margin & binary options layer with no directional risk for LPs, enabling trustless leverage and price bets on any AMM without funding rates or synthetic markets.”**
