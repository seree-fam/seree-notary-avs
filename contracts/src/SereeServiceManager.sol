// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {ECDSAServiceManagerBase} from "@eigenlayer-middleware/src/unaudited/ECDSAServiceManagerBase.sol";
import {ECDSAStakeRegistry} from "@eigenlayer-middleware/src/unaudited/ECDSAStakeRegistry.sol";
import {IServiceManager} from "@eigenlayer-middleware/src/interfaces/IServiceManager.sol";
import {ECDSAUpgradeable} from "@openzeppelin-upgrades/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import {IERC1271Upgradeable} from "@openzeppelin-upgrades/contracts/interfaces/IERC1271Upgradeable.sol";
import {ISereeServiceManager} from "./ISereeServiceManager.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

interface IERC20 {
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);
}

/**
 * @title Primary entrypoint for procuring services from Sereé (https://seree.xyz).
 * @author Eigen Labs, Inc.
 */
contract SereeServiceManager is ECDSAServiceManagerBase, ISereeServiceManager {
    using ECDSAUpgradeable for bytes32;

    bytes32 public latestOrderUuid;

    address constant sBWP_ADDRESS = 0x1234567890abcdef1234567890abcdef12345678;
    address constant sKES_ADDRESS = 0xabcdef1234567890abcdef1234567890abcdef12;
    address constant sNGN_ADDRESS = 0x7890abcdef1234567890abcdef1234567890abcd;
    address constant sGHS_ADDRESS = 0xef1234567890abcdef1234567890abcdef1234;

    // mapping of task indices to all tasks hashes
    // when a task is created, task hash is stored here,
    // and responses need to pass the actual task,
    // which is hashed onchain and checked against this mapping
    // mapping(uint32 => bytes32) public allTaskHashes;

    // mapping of task indices to hash of abi.encode(taskResponse, taskResponseMetadata)
    // mapping(address => mapping(uint32 => bytes)) public allTaskResponses;

    modifier onlyOperator() {
        require(
            ECDSAStakeRegistry(stakeRegistry).operatorRegistered(msg.sender),
            "Operator must be the caller"
        );
        _;
    }

    constructor(
        address _avsDirectory,
        address _stakeRegistry,
        address _rewardsCoordinator,
        address _delegationManager
    )
        ECDSAServiceManagerBase(
            _avsDirectory,
            _stakeRegistry,
            _rewardsCoordinator,
            _delegationManager
        )
    {}

    /* FUNCTIONS */
    function latestOrderUuid() external view returns (bytes32) {
        return latestOrderUuid;
    }

    function createNewOrder(
        bytes32 _uuid,
        Token token,
        uint256 amount
    ) external payable {
        require(amount > 0, "Amount must be greater than 0");

        address tokenAddress;

        if (token == Token.sBWP) {
            tokenAddress = sBWP_ADDRESS;
        } else if (token == Token.sKES) {
            tokenAddress = sKES_ADDRESS;
        } else if (token == Token.sNGN) {
            tokenAddress = sNGN_ADDRESS;
        } else if (token == Token.sGHS) {
            tokenAddress = sGHS_ADDRESS;
        } else {
            revert("Invalid token type");
        }

        uint256 allowance = IERC20(tokenAddress).allowance(
            msg.sender,
            address(this)
        );
        require(allowance >= amount, "Insufficient allowance");

        
    }

    function notarizeOrder(
        bytes32 _uuid,
        bytes calldata signature,
        bytes32 message_hash
    ) external;

    // NOTE: this function creates new task, assigns it a taskId
    function createNewTask(string memory name) external returns (Task memory) {
        // create a new task struct
        Task memory newTask;
        newTask.name = name;
        newTask.taskCreatedBlock = uint32(block.number);

        // store hash of task onchain, emit event, and increase taskNum
        allTaskHashes[latestTaskNum] = keccak256(abi.encode(newTask));
        emit NewTaskCreated(latestTaskNum, newTask);
        latestTaskNum = latestTaskNum + 1;

        return newTask;
    }

    function respondToTask(
        Task calldata task,
        uint32 referenceTaskIndex,
        bytes memory signature
    ) external {
        // check that the task is valid, hasn't been responsed yet, and is being responded in time
        require(
            keccak256(abi.encode(task)) == allTaskHashes[referenceTaskIndex],
            "supplied task does not match the one recorded in the contract"
        );
        require(
            allTaskResponses[msg.sender][referenceTaskIndex].length == 0,
            "Operator has already responded to the task"
        );

        // The message that was signed
        bytes32 messageHash = keccak256(abi.encodePacked("Hello, ", task.name));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        bytes4 magicValue = IERC1271Upgradeable.isValidSignature.selector;
        if (
            !(magicValue ==
                ECDSAStakeRegistry(stakeRegistry).isValidSignature(
                    ethSignedMessageHash,
                    signature
                ))
        ) {
            revert();
        }

        // updating the storage with task responses
        allTaskResponses[msg.sender][referenceTaskIndex] = signature;

        // emitting event
        emit TaskResponded(referenceTaskIndex, task, msg.sender);
    }
}
