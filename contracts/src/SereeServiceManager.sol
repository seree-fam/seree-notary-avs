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
import "./p256/verifier.sol";

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

/**
 * @title Primary entrypoint for procuring services from Sereé (https://seree.xyz).
 * @author Eigen Labs, Inc.
 */
contract SereeServiceManager is ECDSAServiceManagerBase, ISereeServiceManager {
    using ECDSAUpgradeable for bytes32;

    // Sereé Sepolia Address
    address public constant recipient =
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

    bytes32 public latestOrderUuid;

    mapping(uint256 => Order) public orders;
    mapping(uint256 => uint256) public escrowBalances;

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
        address _delegationManager,
        address sBWP_ADDR,
        address sKES_ADDR,
        address sNGN_ADDR,
        address sGHS_ADDR
    )
        ECDSAServiceManagerBase(
            _avsDirectory,
            _stakeRegistry,
            _rewardsCoordinator,
            _delegationManager
        )
    {
        sBWP_ADDRESS = sBWP_ADDR;
        sKES_ADDRESS = sKES_ADDR;
        sNGN_ADDRESS = sNGN_ADDR;
        sGHS_ADDRESS = sGHS_ADDR;
    }

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
        latestOrderUuid = _uuid;

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

        Order memory newOrder = Order({
            uuid: _uuid,
            orderCreatedBlock: uint32(block.number),
            status: Status.Unpaid,
            token: token
        });
        
        orders[uint256(_uuid)] = newOrder;
        escrowBalances[uint256(_uuid)] = amount;

        bool success = IERC20(tokenAddress).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        require(success, "Transfer failed");

        emit OrderPlaced(_uuid);
    }

    function notarizeOrder(
        bytes32 _uuid,
        bytes32 message_hash,
        uint256 r,
        uint256 s,
        uint256 x,
        uint256 y
    ) external {
        SignatureVerifier sigVerifier = new SignatureVerifier();

        bool isValidSignature = sigVerifier.verify(message_hash, r, s, x, y);
        require(isValidSignature, "Invalid signature");

        Order storage order = orders[uint256(_uuid)];
        require(order.status == Status.Unpaid, "Order already paid");

        uint256 amount = escrowBalances[uint256(_uuid)];
        require(amount > 0, "Amount must be greater than 0");

        if (token == Token.sBWP) {
            require(IERC20(sBWP_ADDRESS).transfer(recipient, amount), "Pula transfer failed");
        } else if (token == Token.sKES) {
            require(IERC20(sKES_ADDRESS).transfer(recipient, amount), "Shilling transfer failed");
        } else if (token == Token.sNGN) {
            require(IERC20(sNGN_ADDRESS).transfer(recipient, amount), "Naira transfer failed");
        } else if (token == Token.sGHS) {
            require(IERC20(sGHS_ADDRESS).transfer(recipient, amount), "Cedi transfer failed");
        } else {
            revert("Invalid token type");
        }

        order.status = Status.Paid;
        escrowBalances[uint256(_uuid)] = 0;

        emit Payout(_uuid);
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
