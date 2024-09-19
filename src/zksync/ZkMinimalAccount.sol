// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ZkSync Foundry Era
import {IAccount, ACCOUNT_VALIDATION_SUCCESS_MAGIC} from "@foundry-era-contracts/contracts/interfaces/IAccount.sol";
import {
    Transaction,
    MemoryTransactionHelper
} from "@foundry-era-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {SystemContractsCaller} from "@foundry-era-contracts/contracts/libraries/SystemContractsCaller.sol";
import {
    NONCE_HOLDER_SYSTEM_CONTRACT,
    BOOTLOADER_FORMAL_ADDRESS,
    DEPLOYER_SYSTEM_CONTRACT
} from "@foundry-era-contracts/contracts/Constants.sol";
import {INonceHolder} from "@foundry-era-contracts/contracts/interfaces/INonceHolder.sol";
import {Utils} from "@foundry-era-contracts/contracts/libraries/Utils.sol";

// OpenZeppelin
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * Lifecycle of a type 113 (0x71) transaction
 * msg.sender is the bootloader system contract
 *
 * Phase 1: Validation
 * 1. The user sends the transaction to the "zkSync API client" (sort of a "light node")
 * 2. The zkSync API client checks to see the nonce is unique by querying the NonceHolder system contract
 * 3. The zkSync API client calls validateTransaction, which MUST update the nonce
 * 4. The zkSync API client checks the nonce is updated
 * 5. The zkSync API client calls payForTransaction, or prepareForPaymaster & validateAndPayForPaymasterTransaction
 * 6. The zkSync API client verifies that the bootloader gets paid
 *
 * Phase 2: Execution
 * 7. The zkSync API client passes the validated transaction to the main node / sequencer (as of today, they are the same)
 * 8. The main node calls executeTransaction
 * 9. If a paymaster was used, the postTransaction is called
 */
contract ZkMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;

    error ZkMinimalAccount__NotEnoughBalance();
    error ZkMinimalAccount__NotFromBootLoader();
    error ZkMinimalAccount__ExecutionFailed();
    error ZkMinimalAccount__NotFromBootLoaderOrOwner();
    error ZkMinimalAccount__FailedToPay();

    constructor() Ownable(msg.sender) {}

    /*////////////////////////////////////////////////////////////////////
    // Modifiers
    ////////////////////////////////////////////////////////////////////*/
    modifier requireFromBootLoader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) {
            revert ZkMinimalAccount__NotFromBootLoader();
        }
        _;
    }

    modifier requireFromBootLoaderOrOwner() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS && msg.sender != owner()) {
            revert ZkMinimalAccount__NotFromBootLoaderOrOwner();
        }
        _;
    }

    /*////////////////////////////////////////////////////////////////////
    // External Functions
    ////////////////////////////////////////////////////////////////////*/
    /**
     * @notice must increase the nonce
     * @notice must validate the transaction (check the owner signed the transaction)
     * @notice also check to see if we have enough money in our account
     */
    function validateTransaction(
        bytes32, /* _txHash */
        bytes32, /*_suggestedSignedHash*/
        Transaction memory _transaction
    ) external payable requireFromBootLoader returns (bytes4 magic) {
        // Call nonceholder
        // increment nonce
        // call(x, y, z) --> system contract call
        SystemContractsCaller.systemCallWithPropagatedRevert(
            uint32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, (_transaction.nonce))
        );

        // Check for fee to pay
        uint256 totalRequiredBalance = _transaction.totalRequiredBalance();
        if (totalRequiredBalance > address(this).balance) {
            revert ZkMinimalAccount__NotEnoughBalance();
        }

        // Check the signature
        bytes32 txHash = _transaction.encodeHash();
        bytes32 convertedHash = MessageHashUtils.toEthSignedMessageHash(txHash);
        address signer = ECDSA.recover(convertedHash, _transaction.signature);
        bool isValidSigner = signer == owner();
        if (isValidSigner) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }

        // return the "magic" number
        return magic;
    }

    function executeTransaction(
        bytes32, /* _txHash */
        bytes32, /*_suggestedSignedHash*/
        Transaction memory _transaction
    ) external payable requireFromBootLoaderOrOwner {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;

        if (to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            uint32 gas = Utils.safeCastToU32(gasleft());
            SystemContractsCaller.systemCallWithPropagatedRevert(gas, to, value, data);
        } else {
            bool sucess;
            assembly {
                sucess := call(gas(), to, value, add(data, 0x20), mload(data), 0, 0)
            }
            if (!sucess) {
                revert ZkMinimalAccount__ExecutionFailed();
            }
        }
    }

    function executeTransactionFromOutside(Transaction memory _transaction) external payable {}

    function payForTransaction(bytes32, /* _txHash */ bytes32, /*_suggestedSignedHash*/ Transaction memory _transaction)
        external
        payable
    {
        bool sucess = _transaction.payToTheBootloader();
        if (!sucess) {
            revert ZkMinimalAccount__FailedToPay();
        }
    }

    function prepareForPaymaster(bytes32 _txHash, bytes32 _possibleSignedHash, Transaction memory _transaction)
        external
        payable
    {}
    /*////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////*/
}
