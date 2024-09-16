// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {MinimalAccount} from "src/ethereum/MinimalAccount.sol";
import {DeployMinimal} from "script/DeployMinimal.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {SendPackedUserOp, PackedUserOperation} from "script/SendPackedUserOp.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MinimalAccountTest is Test {
    using MessageHashUtils for bytes32;

    error MinimalAccount__NotFromEntryPointOrOwner();

    MinimalAccount minimalAccount;
    HelperConfig config;
    ERC20Mock usdc;
    SendPackedUserOp sendPackedUserOp;

    address randomUser = makeAddr("randomUser");
    uint256 constant AMOUNT = 1e18;

    function setUp() public {
        DeployMinimal deployer = new DeployMinimal();
        (config, minimalAccount) = deployer.run();
        usdc = new ERC20Mock();
        sendPackedUserOp = new SendPackedUserOp();
    }

    // USDC Approval

    // msg.sender -> MinimalAccount
    // approve some amount
    // USDC contract
    // come from the entrypoint

    function testOwnerCanExecuteCommands() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        // Act
        vm.prank(minimalAccount.owner());
        minimalAccount.execute(dest, value, functionData);
        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }

    function testNonOwnerCannotExecuteCommands() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        // Act
        vm.prank(randomUser);
        vm.expectRevert(MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.execute(dest, value, functionData);
    }

    function testRecoverSignedOp() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory packedUserOp =
            sendPackedUserOp.generateSignedUserOperation(executeCallData, config.getConfig());
        bytes32 userOperationHash = IEntryPoint(config.getConfig().entryPoint).getUserOpHash(packedUserOp);

        // Act
        address actualSigner = ECDSA.recover(userOperationHash.toEthSignedMessageHash(), packedUserOp.signature);

        // Assert
        assertEq(actualSigner, minimalAccount.owner());
    }
}
