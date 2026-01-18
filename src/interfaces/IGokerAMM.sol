// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IGokerAMM
 * @notice Interface for the Goker AMM contract
 */
interface IGokerAMM {
    // Events
    event LiquidityAdded(address indexed provider, uint256 amount, uint256 shares);
    event LiquidityRemoved(address indexed provider, uint256 amount, uint256 shares);
    event Swap(
        address indexed trader,
        bool isBuy,
        uint256 amountIn,
        uint256 amountOut,
        uint256 price
    );
    event FeeUpdated(uint256 newBidFee, uint256 newAskFee);
    event StrategistUpdated(address indexed newStrategist);

    // Errors
    error InsufficientLiquidity();
    error InsufficientOutput();
    error InvalidAmount();
    error Unauthorized();
    error SlippageExceeded();

    /**
     * @notice Add liquidity to the AMM
     * @param amount Amount of base token to add
     * @return shares Amount of LP shares minted
     */
    function addLiquidity(uint256 amount) external returns (uint256 shares);

    /**
     * @notice Remove liquidity from the AMM
     * @param shares Amount of LP shares to burn
     * @return amount Amount of base token returned
     */
    function removeLiquidity(uint256 shares) external returns (uint256 amount);

    /**
     * @notice Execute a swap
     * @param isBuy True for buy, false for sell
     * @param amountIn Amount of input token
     * @param minAmountOut Minimum acceptable output amount
     * @return amountOut Actual output amount
     */
    function swap(
        bool isBuy,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut);

    /**
     * @notice Get current bid price (price to sell)
     * @return price The bid price scaled by 1e8
     */
    function getBidPrice() external view returns (uint256 price);

    /**
     * @notice Get current ask price (price to buy)
     * @return price The ask price scaled by 1e8
     */
    function getAskPrice() external view returns (uint256 price);

    /**
     * @notice Get the current spread
     * @return spread The bid-ask spread in basis points
     */
    function getSpread() external view returns (uint256 spread);

    /**
     * @notice Get total liquidity in the pool
     * @return liquidity Total liquidity amount
     */
    function getTotalLiquidity() external view returns (uint256 liquidity);

    /**
     * @notice Get LP share balance
     * @param account The account to query
     * @return shares LP share balance
     */
    function balanceOf(address account) external view returns (uint256 shares);

    /**
     * @notice Get total LP shares
     * @return totalShares Total LP shares outstanding
     */
    function totalShares() external view returns (uint256 totalShares);
}
