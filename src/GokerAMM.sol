// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IGokerAMM} from "./interfaces/IGokerAMM.sol";
import {IL1Read, L1ReadLib} from "./interfaces/IL1Read.sol";
import {DynamicFeeModule} from "./modules/DynamicFeeModule.sol";

/**
 * @title GokerAMM
 * @notice Automated Market Maker for Goker on HyperEVM
 * @dev Uses L1Read precompile for oracle prices and dynamic fees
 *
 * This is a Valantis-style AMM POC that:
 * - Reads oracle prices from HyperCore via L1Read precompile
 * - Implements dynamic bid/ask spread based on volatility and inventory
 * - Allows strategist to manage liquidity allocation
 */
contract GokerAMM is IGokerAMM {
    using L1ReadLib for uint256;

    // Token addresses (simplified - using native ETH and a quote token)
    address public immutable quoteToken;  // USDC or similar
    uint256 public immutable coinIndex;   // Coin index for L1Read

    // Liquidity state
    uint256 private _totalShares;
    uint256 private _totalLiquidity;
    mapping(address => uint256) private _shares;

    // Fee module
    DynamicFeeModule public feeModule;

    // Roles
    address public owner;
    address public strategist;

    // Constants
    uint256 public constant PRICE_DECIMALS = 1e8;
    uint256 public constant FEE_DENOMINATOR = 10000;  // Basis points
    uint256 public constant MIN_LIQUIDITY = 1000;     // Minimum liquidity to prevent division issues

    // Modifiers
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyStrategist() {
        if (msg.sender != strategist && msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor(
        address _quoteToken,
        uint256 _coinIndex,
        uint256 baseBidFee,
        uint256 baseAskFee
    ) {
        owner = msg.sender;
        strategist = msg.sender;
        quoteToken = _quoteToken;
        coinIndex = _coinIndex;

        // Deploy fee module
        feeModule = new DynamicFeeModule(
            baseBidFee,   // Base bid fee (e.g., 10 = 0.10%)
            baseAskFee,   // Base ask fee (e.g., 10 = 0.10%)
            100,          // Max fee (1%)
            1             // Min fee (0.01%)
        );
    }

    /**
     * @inheritdoc IGokerAMM
     */
    function addLiquidity(uint256 amount) external returns (uint256 shares) {
        if (amount == 0) revert InvalidAmount();

        // Transfer quote tokens to this contract
        // In production, use SafeERC20
        (bool success,) = quoteToken.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                msg.sender,
                address(this),
                amount
            )
        );
        require(success, "Transfer failed");

        // Calculate shares
        if (_totalShares == 0) {
            shares = amount;
        } else {
            shares = (amount * _totalShares) / _totalLiquidity;
        }

        if (shares == 0) revert InvalidAmount();

        _shares[msg.sender] += shares;
        _totalShares += shares;
        _totalLiquidity += amount;

        emit LiquidityAdded(msg.sender, amount, shares);
    }

    /**
     * @inheritdoc IGokerAMM
     */
    function removeLiquidity(uint256 shares) external returns (uint256 amount) {
        if (shares == 0 || shares > _shares[msg.sender]) revert InvalidAmount();

        amount = (shares * _totalLiquidity) / _totalShares;

        if (_totalLiquidity - amount < MIN_LIQUIDITY && _totalLiquidity > MIN_LIQUIDITY) {
            revert InsufficientLiquidity();
        }

        _shares[msg.sender] -= shares;
        _totalShares -= shares;
        _totalLiquidity -= amount;

        // Transfer quote tokens back
        (bool success,) = quoteToken.call(
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                msg.sender,
                amount
            )
        );
        require(success, "Transfer failed");

        emit LiquidityRemoved(msg.sender, amount, shares);
    }

    /**
     * @inheritdoc IGokerAMM
     */
    function swap(
        bool isBuy,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut) {
        if (amountIn == 0) revert InvalidAmount();
        if (_totalLiquidity < MIN_LIQUIDITY) revert InsufficientLiquidity();

        uint256 price;
        uint256 fee;

        if (isBuy) {
            // Buying: user sends quote, receives base amount
            price = getAskPrice();
            fee = feeModule.calculateAskFee(coinIndex, amountIn);

            // Calculate output after fee
            uint256 amountAfterFee = amountIn * (FEE_DENOMINATOR - fee) / FEE_DENOMINATOR;
            amountOut = (amountAfterFee * PRICE_DECIMALS) / price;

        } else {
            // Selling: user sends base amount, receives quote
            price = getBidPrice();
            fee = feeModule.calculateBidFee(coinIndex, amountIn);

            // Calculate output before fee
            uint256 grossOutput = (amountIn * price) / PRICE_DECIMALS;
            amountOut = grossOutput * (FEE_DENOMINATOR - fee) / FEE_DENOMINATOR;
        }

        if (amountOut < minAmountOut) revert SlippageExceeded();

        // Execute the swap
        if (isBuy) {
            // Receive quote token
            (bool success,) = quoteToken.call(
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    msg.sender,
                    address(this),
                    amountIn
                )
            );
            require(success, "Transfer in failed");

            _totalLiquidity += amountIn;

            // Note: In a real implementation, we would also transfer the base asset
            // For this POC, we're simulating the swap

        } else {
            // Send quote token
            if (amountOut > _totalLiquidity) revert InsufficientLiquidity();

            (bool success,) = quoteToken.call(
                abi.encodeWithSignature(
                    "transfer(address,uint256)",
                    msg.sender,
                    amountOut
                )
            );
            require(success, "Transfer out failed");

            _totalLiquidity -= amountOut;
        }

        // Update fee module inventory
        int256 skewDelta = isBuy ? int256(amountIn) : -int256(amountOut);
        feeModule.updateInventorySkew(skewDelta);

        emit Swap(msg.sender, isBuy, amountIn, amountOut, price);
    }

    /**
     * @inheritdoc IGokerAMM
     */
    function getBidPrice() public view returns (uint256 price) {
        uint256 oraclePrice = L1ReadLib.getOraclePrice(coinIndex);
        uint256 bidFee = feeModule.calculateBidFee(coinIndex, 0);

        // Bid price = oracle price * (1 - fee)
        price = oraclePrice * (FEE_DENOMINATOR - bidFee) / FEE_DENOMINATOR;
    }

    /**
     * @inheritdoc IGokerAMM
     */
    function getAskPrice() public view returns (uint256 price) {
        uint256 oraclePrice = L1ReadLib.getOraclePrice(coinIndex);
        uint256 askFee = feeModule.calculateAskFee(coinIndex, 0);

        // Ask price = oracle price * (1 + fee)
        price = oraclePrice * (FEE_DENOMINATOR + askFee) / FEE_DENOMINATOR;
    }

    /**
     * @inheritdoc IGokerAMM
     */
    function getSpread() external view returns (uint256 spread) {
        uint256 bid = getBidPrice();
        uint256 ask = getAskPrice();

        // Spread in basis points
        spread = ((ask - bid) * FEE_DENOMINATOR) / bid;
    }

    /**
     * @inheritdoc IGokerAMM
     */
    function getTotalLiquidity() external view returns (uint256) {
        return _totalLiquidity;
    }

    /**
     * @inheritdoc IGokerAMM
     */
    function balanceOf(address account) external view returns (uint256) {
        return _shares[account];
    }

    /**
     * @inheritdoc IGokerAMM
     */
    function totalShares() external view returns (uint256) {
        return _totalShares;
    }

    /**
     * @notice Get current oracle price from L1Read
     * @return price The oracle price scaled by 1e8
     */
    function getOraclePrice() external view returns (uint256 price) {
        return L1ReadLib.getOraclePrice(coinIndex);
    }

    /**
     * @notice Set the strategist address
     * @param _strategist New strategist address
     */
    function setStrategist(address _strategist) external onlyOwner {
        if (_strategist == address(0)) revert InvalidAmount();
        strategist = _strategist;
        emit StrategistUpdated(_strategist);
    }

    /**
     * @notice Update fee module parameters (strategist function)
     * @param baseBidFee New base bid fee
     * @param baseAskFee New base ask fee
     * @param maxFee New max fee
     * @param minFee New min fee
     */
    function updateFees(
        uint256 baseBidFee,
        uint256 baseAskFee,
        uint256 maxFee,
        uint256 minFee
    ) external onlyStrategist {
        feeModule.setFeeParameters(baseBidFee, baseAskFee, maxFee, minFee);
        emit FeeUpdated(baseBidFee, baseAskFee);
    }

    /**
     * @notice Trigger price update for volatility tracking
     */
    function updatePriceTracking() external {
        feeModule.updatePrice(coinIndex);
    }

    /**
     * @notice Transfer ownership
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAmount();
        owner = newOwner;
    }
}
