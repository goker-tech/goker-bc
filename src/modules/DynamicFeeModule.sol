// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IL1Read, L1ReadLib} from "../interfaces/IL1Read.sol";

/**
 * @title DynamicFeeModule
 * @notice Module for calculating dynamic fees based on market conditions
 * @dev Uses L1Read precompile to get oracle prices and adjust fees
 */
contract DynamicFeeModule {
    using L1ReadLib for uint256;

    // Fee configuration
    uint256 public baseBidFee;  // Base fee for sells (in basis points)
    uint256 public baseAskFee;  // Base fee for buys (in basis points)
    uint256 public maxFee;      // Maximum fee cap
    uint256 public minFee;      // Minimum fee floor

    // Volatility parameters
    uint256 public volatilityMultiplier;  // How much volatility affects fees
    uint256 public lastPrice;
    uint256 public priceUpdateTime;
    uint256 public volatilityWindow;      // Time window for volatility calculation

    // Inventory parameters
    int256 public inventorySkew;          // Current inventory imbalance
    uint256 public inventoryMultiplier;   // How much inventory affects fees

    // Owner
    address public owner;

    // Events
    event FeesUpdated(uint256 bidFee, uint256 askFee);
    event ParametersUpdated(
        uint256 baseBidFee,
        uint256 baseAskFee,
        uint256 maxFee,
        uint256 minFee
    );

    // Errors
    error Unauthorized();
    error InvalidParameter();

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor(
        uint256 _baseBidFee,
        uint256 _baseAskFee,
        uint256 _maxFee,
        uint256 _minFee
    ) {
        owner = msg.sender;
        baseBidFee = _baseBidFee;
        baseAskFee = _baseAskFee;
        maxFee = _maxFee;
        minFee = _minFee;
        volatilityMultiplier = 100;  // 1x multiplier
        inventoryMultiplier = 50;    // 0.5x multiplier
        volatilityWindow = 1 hours;
    }

    /**
     * @notice Calculate dynamic bid fee (for sells)
     * @param coin The coin index for price lookup
     * @param tradeSize The size of the trade
     * @return fee The calculated fee in basis points
     */
    function calculateBidFee(
        uint256 coin,
        uint256 tradeSize
    ) external view returns (uint256 fee) {
        fee = baseBidFee;

        // Adjust for volatility
        uint256 volatilityAdjustment = _calculateVolatilityAdjustment(coin);
        fee = fee + (volatilityAdjustment * volatilityMultiplier) / 100;

        // Adjust for inventory (incentivize balancing)
        if (inventorySkew > 0) {
            // Long inventory - incentivize sells with lower fee
            uint256 inventoryDiscount = uint256(inventorySkew) * inventoryMultiplier / 10000;
            fee = fee > inventoryDiscount ? fee - inventoryDiscount : minFee;
        } else if (inventorySkew < 0) {
            // Short inventory - discourage sells with higher fee
            uint256 inventoryPremium = uint256(-inventorySkew) * inventoryMultiplier / 10000;
            fee = fee + inventoryPremium;
        }

        // Apply bounds
        fee = _boundFee(fee);
    }

    /**
     * @notice Calculate dynamic ask fee (for buys)
     * @param coin The coin index for price lookup
     * @param tradeSize The size of the trade
     * @return fee The calculated fee in basis points
     */
    function calculateAskFee(
        uint256 coin,
        uint256 tradeSize
    ) external view returns (uint256 fee) {
        fee = baseAskFee;

        // Adjust for volatility
        uint256 volatilityAdjustment = _calculateVolatilityAdjustment(coin);
        fee = fee + (volatilityAdjustment * volatilityMultiplier) / 100;

        // Adjust for inventory (incentivize balancing)
        if (inventorySkew < 0) {
            // Short inventory - incentivize buys with lower fee
            uint256 inventoryDiscount = uint256(-inventorySkew) * inventoryMultiplier / 10000;
            fee = fee > inventoryDiscount ? fee - inventoryDiscount : minFee;
        } else if (inventorySkew > 0) {
            // Long inventory - discourage buys with higher fee
            uint256 inventoryPremium = uint256(inventorySkew) * inventoryMultiplier / 10000;
            fee = fee + inventoryPremium;
        }

        // Apply bounds
        fee = _boundFee(fee);
    }

    /**
     * @notice Calculate volatility adjustment based on recent price movement
     * @param coin The coin index
     * @return adjustment Fee adjustment in basis points
     */
    function _calculateVolatilityAdjustment(uint256 coin) internal view returns (uint256 adjustment) {
        if (lastPrice == 0 || block.timestamp - priceUpdateTime > volatilityWindow) {
            return 0;
        }

        // Get current oracle price
        uint256 currentPrice = L1ReadLib.getOraclePrice(coin);

        // Calculate price change percentage (scaled by 10000 for precision)
        uint256 priceDiff;
        if (currentPrice > lastPrice) {
            priceDiff = ((currentPrice - lastPrice) * 10000) / lastPrice;
        } else {
            priceDiff = ((lastPrice - currentPrice) * 10000) / lastPrice;
        }

        // Higher volatility = higher fees
        // 1% price change = 10 bps fee increase
        adjustment = priceDiff / 10;
    }

    /**
     * @notice Bound fee within min/max range
     * @param fee The raw fee
     * @return boundedFee The bounded fee
     */
    function _boundFee(uint256 fee) internal view returns (uint256 boundedFee) {
        if (fee < minFee) return minFee;
        if (fee > maxFee) return maxFee;
        return fee;
    }

    /**
     * @notice Update inventory skew (called by AMM after trades)
     * @param newSkew The new inventory skew value
     */
    function updateInventorySkew(int256 newSkew) external {
        // In production, this should be restricted to the AMM contract
        inventorySkew = newSkew;
    }

    /**
     * @notice Update price for volatility tracking
     * @param coin The coin index
     */
    function updatePrice(uint256 coin) external {
        lastPrice = L1ReadLib.getOraclePrice(coin);
        priceUpdateTime = block.timestamp;
    }

    /**
     * @notice Update fee parameters
     * @param _baseBidFee New base bid fee
     * @param _baseAskFee New base ask fee
     * @param _maxFee New max fee
     * @param _minFee New min fee
     */
    function setFeeParameters(
        uint256 _baseBidFee,
        uint256 _baseAskFee,
        uint256 _maxFee,
        uint256 _minFee
    ) external onlyOwner {
        if (_minFee > _maxFee) revert InvalidParameter();
        if (_baseBidFee > _maxFee || _baseAskFee > _maxFee) revert InvalidParameter();

        baseBidFee = _baseBidFee;
        baseAskFee = _baseAskFee;
        maxFee = _maxFee;
        minFee = _minFee;

        emit ParametersUpdated(_baseBidFee, _baseAskFee, _maxFee, _minFee);
    }

    /**
     * @notice Update multiplier parameters
     * @param _volatilityMultiplier New volatility multiplier
     * @param _inventoryMultiplier New inventory multiplier
     */
    function setMultipliers(
        uint256 _volatilityMultiplier,
        uint256 _inventoryMultiplier
    ) external onlyOwner {
        volatilityMultiplier = _volatilityMultiplier;
        inventoryMultiplier = _inventoryMultiplier;
    }

    /**
     * @notice Transfer ownership
     * @param newOwner The new owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidParameter();
        owner = newOwner;
    }
}
