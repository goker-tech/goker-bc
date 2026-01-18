// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {GokerAMM, IGokerAMM} from "../src/GokerAMM.sol";
import {DynamicFeeModule} from "../src/modules/DynamicFeeModule.sol";

/**
 * @title MockERC20
 * @notice Simple mock ERC20 for testing
 */
contract MockERC20 {
    string public name = "Mock USDC";
    string public symbol = "mUSDC";
    uint8 public decimals = 6;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        allowance[from][msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract GokerAMMTest is Test {
    GokerAMM public amm;
    MockERC20 public usdc;

    address public owner = address(this);
    address public alice = address(0x1);
    address public bob = address(0x2);

    uint256 constant INITIAL_LIQUIDITY = 1_000_000 * 1e6;  // 1M USDC

    function setUp() public {
        // Deploy mocks
        usdc = new MockERC20();

        // Mock the L1Read precompile at 0x0800 to return a fixed price
        // When getOraclePrice(uint256) is called, return 50000 * 1e8
        bytes memory mockCode = hex"608060405234801561001057600080fd5b506004361061002b5760003560e01c80632d3e474e14610030575b600080fd5b61004a600480360381019061004591906100a9565b610060565b60405161005791906100e5565b60405180910390f35b60006512309ce54000905092915050565b600080fd5b6000819050919050565b61008681610076565b811461009157600080fd5b50565b6000813590506100a38161007d565b92915050565b6000602082840312156100bf576100be610071565b5b60006100cd84828501610094565b91505092915050565b6100df81610076565b82525050565b60006020820190506100fa60008301846100d6565b9291505056fea264697066735822122089c89c89c89c89c89c89c89c89c89c89c89c89c89c89c89c89c89c89c89c89c864736f6c63430008140033";
        vm.etch(address(0x0800), mockCode);

        // Deploy AMM
        amm = new GokerAMM(
            address(usdc),
            0,              // BTC coin index
            10,             // 0.10% base bid fee
            10              // 0.10% base ask fee
        );

        // Fund accounts
        usdc.mint(owner, INITIAL_LIQUIDITY * 2);
        usdc.mint(alice, INITIAL_LIQUIDITY);
        usdc.mint(bob, INITIAL_LIQUIDITY);

        // Approve AMM
        usdc.approve(address(amm), type(uint256).max);
        vm.prank(alice);
        usdc.approve(address(amm), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(amm), type(uint256).max);
    }

    function test_AddLiquidity() public {
        uint256 amount = 100_000 * 1e6;

        uint256 shares = amm.addLiquidity(amount);

        assertEq(shares, amount, "First deposit should get 1:1 shares");
        assertEq(amm.balanceOf(owner), shares, "Owner should have shares");
        assertEq(amm.getTotalLiquidity(), amount, "Total liquidity should match");
    }

    function test_AddLiquidity_Multiple() public {
        // First deposit
        amm.addLiquidity(100_000 * 1e6);

        // Second deposit by alice
        vm.prank(alice);
        uint256 aliceShares = amm.addLiquidity(50_000 * 1e6);

        assertEq(aliceShares, 50_000 * 1e6, "Alice should get proportional shares");
        assertEq(amm.getTotalLiquidity(), 150_000 * 1e6, "Total liquidity should be sum");
    }

    function test_RemoveLiquidity() public {
        uint256 amount = 100_000 * 1e6;
        uint256 shares = amm.addLiquidity(amount);

        uint256 balanceBefore = usdc.balanceOf(owner);

        // Remove half (must keep MIN_LIQUIDITY)
        uint256 toRemove = shares / 2;
        uint256 withdrawn = amm.removeLiquidity(toRemove);

        assertTrue(withdrawn > 0, "Should withdraw some amount");
        assertEq(amm.balanceOf(owner), shares - toRemove, "Should have remaining shares");
    }

    function test_SetStrategist() public {
        address newStrategist = address(0x999);

        amm.setStrategist(newStrategist);

        assertEq(amm.strategist(), newStrategist, "Strategist should be updated");
    }

    function test_UpdateFees() public {
        // This just verifies the function doesn't revert
        amm.updateFees(20, 20, 200, 5);

        // Verify fee module was updated
        DynamicFeeModule feeModule = amm.feeModule();
        assertEq(feeModule.baseBidFee(), 20, "Base bid fee should be updated");
    }

    function test_RevertWhen_AddLiquidity_ZeroAmount() public {
        vm.expectRevert(IGokerAMM.InvalidAmount.selector);
        amm.addLiquidity(0);
    }

    function test_RevertWhen_RemoveLiquidity_TooMuch() public {
        amm.addLiquidity(100_000 * 1e6);
        vm.expectRevert(IGokerAMM.InvalidAmount.selector);
        amm.removeLiquidity(200_000 * 1e6);  // More than we have
    }

    function test_RevertWhen_SetStrategist_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(IGokerAMM.Unauthorized.selector);
        amm.setStrategist(alice);
    }

    function test_FeeModule_Parameters() public view {
        DynamicFeeModule feeModule = amm.feeModule();

        assertEq(feeModule.baseBidFee(), 10, "Base bid fee should be 10 bps");
        assertEq(feeModule.baseAskFee(), 10, "Base ask fee should be 10 bps");
        assertEq(feeModule.maxFee(), 100, "Max fee should be 100 bps");
        assertEq(feeModule.minFee(), 1, "Min fee should be 1 bp");
    }
}
