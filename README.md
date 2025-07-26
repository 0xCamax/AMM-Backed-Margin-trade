# AMM-Backed Margin Trading Protocol

## 📖 Definition

**An on-chain leveraged margin trading protocol that integrates AMMs as the source of real liquidity.**  

Traders can open leveraged positions on spot assets without synthetic counterparts or funding rates, while LPs act solely as margin lenders, earning stable yield without taking directional risk or impermanent loss.

---

## 🔑 Key Components

1. **Real liquidity (AMMs)**
   - All operations are executed **1:1** against AMMs like Uniswap or Curve.
   - No synthetic markets or virtual order books.

2. **Margin Lending Pool (LPs)**
   - LPs deposit **stablecoins** to provide extra margin for traders.
   - Earn **borrow rate** proportional to pool utilization.
   - **No directional exposure or IL**, only liquidation risk.

3. **Leveraged traders**
   - Deposit collateral and borrow additional margin from the pool.
   - Positions are physically backed in the AMM.
   - Pay **interest to the pool** and face liquidation if losses exceed the threshold.

4. **Liquidation Engine**
   - Monitors the PnL of each position.
   - If the value falls below the threshold → liquidates and repays the pool first.

---

## 🆚 Differences from other models

| Model                      | Liquidity            | Funding Rate | Counterparty      | LPs take directional risk |
|----------------------------|---------------------|--------------|-------------------|---------------------------|
| **Synthetic perp (dYdX)**  | Virtual             | ✅ Yes       | Traders vs traders | ❌ |
| **Perp with vault (GMX)**  | Oracle              | ✅ Yes (skew)| LP vault          | ✅ |
| **Your model**             | **Real AMM spot**   | ❌ No        | AMM spot          | ❌ |

---

## 💡 Value Proposition

- **For traders**  
  Enables **on-chain leverage on existing liquidity** without searching for counterparties.

- **For LPs**  
  Provides **stable APY with no IL**, unlike providing liquidity in AMMs or acting as GMX counterparties.

- **For the protocol**  
  No need for **funding rates or complex order books**, as it always operates on real spot prices.

---

## 🎯 Similarities / Differences

- ✅ Similar to **Aave + Uniswap**, but integrated into a single flow (open leverage = borrow + swap in 1 tx).  
- ✅ Similar to **marginfi (Solana)** or **Synthetix Perps with delegated margin**, but using real liquidity.  
- ❌ Not like dYdX or GMX, because it **doesn’t create an isolated perp market**, it only provides leverage on AMMs.

---

## 📝 Elevator pitch

> **“A margin layer with no directional risk for LPs, enabling trustless leverage on any on-chain AMM without funding rates or synthetic markets.”**
