// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IAccount} from "lib/account-abstraction/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "lib/account-abstraction/contracts/core/Helpers.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";

contract MinimalAccount is IAccount, Ownable {
    /*////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////*/
    error MinimalAccount__NotFromEntryPoint();
    error MinimalAccount__NotFromEntryPointOrOwner();
    error MinimalAccount__CallFailed(bytes);

    /*////////////////////////////////////////////////////////////////////
    // State Variables
    ////////////////////////////////////////////////////////////////////*/
    // entry point -> this contract
    IEntryPoint private immutable i_entryPoint;

    /*////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////*/
    event Received(address indexed sender, uint256 amount);

    /*////////////////////////////////////////////////////////////////////
    // Modifiers
    ////////////////////////////////////////////////////////////////////*/
    modifier requireFromEntryPoint() {
        require(msg.sender == address(i_entryPoint), MinimalAccount__NotFromEntryPoint());
        _;
    }

    modifier requireFromEntryPointOrOwner() {
        require(
            msg.sender == address(i_entryPoint) || msg.sender == owner(), MinimalAccount__NotFromEntryPointOrOwner()
        );
        _;
    }

    constructor(address _entryPoint) Ownable(msg.sender) {
        i_entryPoint = IEntryPoint(_entryPoint);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /*////////////////////////////////////////////////////////////////////
    // External Functions
    ////////////////////////////////////////////////////////////////////*/
    function execute(address dest, uint256 value, bytes calldata functionData) external requireFromEntryPointOrOwner {
        (bool sucess, bytes memory result) = dest.call{value: value}(functionData);
        require(sucess, MinimalAccount__CallFailed(result));
    }

    // A signature is valid, if it's the MinimalAccount owner
    function validateUserOp(PackedUserOperation calldata _userOp, bytes32 _userOpHash, uint256 _missingAccountFunds)
        external
        returns (uint256 validationData)
    {
        validationData = _validateSignature(_userOp, _userOpHash);
        // _validateNonce()
        _payPrefund(_missingAccountFunds);
    }

    /*////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////*/
    function _validateSignature(PackedUserOperation calldata _userOp, bytes32 _userOpHash)
        internal
        view
        returns (uint256 validationData)
    {
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(_userOpHash);
        address signer = ECDSA.recover(ethSignedMessageHash, _userOp.signature);
        if (signer != owner()) {
            return SIG_VALIDATION_FAILED;
        }
        return SIG_VALIDATION_SUCCESS;
    }

    function _payPrefund(uint256 _missingAccountFunds) internal {
        if (_missingAccountFunds != 0) {
            (bool sucess,) = payable(msg.sender).call{value: _missingAccountFunds, gas: type(uint256).max}("");
            (sucess);
        }
    }

    /*////////////////////////////////////////////////////////////////////
    // GETTERS
    ////////////////////////////////////////////////////////////////////*/
    function getEntryPoint() external view returns (address) {
        return address(i_entryPoint);
    }
}
