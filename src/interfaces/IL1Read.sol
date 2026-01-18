// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IL1Read
 * @notice Interface for HyperCore L1Read precompile at address 0x0800
 * @dev This precompile provides read-only access to Hyperliquid L1 state
 */
interface IL1Read {
    /**
     * @notice Get the oracle price for a coin
     * @param coin The coin index (0 = BTC, 1 = ETH, etc.)
     * @return price The oracle price scaled by 1e8
     */
    function getOraclePrice(uint256 coin) external view returns (uint256 price);

    /**
     * @notice Get the mark price for a coin
     * @param coin The coin index
     * @return price The mark price scaled by 1e8
     */
    function getMarkPrice(uint256 coin) external view returns (uint256 price);

    /**
     * @notice Get the spot oracle price for a coin
     * @param coin The coin index
     * @return price The spot price scaled by 1e8
     */
    function getSpotOraclePrice(uint256 coin) external view returns (uint256 price);

    /**
     * @notice Get the L1 block number
     * @return blockNumber The current L1 block number
     */
    function getL1BlockNumber() external view returns (uint256 blockNumber);

    /**
     * @notice Get open interest for a coin
     * @param coin The coin index
     * @return openInterest The total open interest
     */
    function getOpenInterest(uint256 coin) external view returns (uint256 openInterest);

    /**
     * @notice Get funding rate for a coin
     * @param coin The coin index
     * @return fundingRate The current funding rate scaled by 1e8
     */
    function getFundingRate(uint256 coin) external view returns (int256 fundingRate);
}

/**
 * @title L1ReadLib
 * @notice Library for interacting with the L1Read precompile
 */
library L1ReadLib {
    address constant L1_READ_PRECOMPILE = address(0x0800);

    /**
     * @notice Get oracle price using the precompile
     * @param coin The coin index
     * @return price The oracle price
     */
    function getOraclePrice(uint256 coin) internal view returns (uint256 price) {
        IL1Read l1Read = IL1Read(L1_READ_PRECOMPILE);
        return l1Read.getOraclePrice(coin);
    }

    /**
     * @notice Get mark price using the precompile
     * @param coin The coin index
     * @return price The mark price
     */
    function getMarkPrice(uint256 coin) internal view returns (uint256 price) {
        IL1Read l1Read = IL1Read(L1_READ_PRECOMPILE);
        return l1Read.getMarkPrice(coin);
    }
}
