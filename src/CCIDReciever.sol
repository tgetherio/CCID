// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/ccip/interfaces/Client.sol";
import "./CCIDIndividualManager.sol";

/**
 * @title CCIDReceiver
 * @notice Receives CCIP messages, verifies sender authenticity, and routes function calls.
 */
contract CCIDReceiver is Ownable {
    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    mapping(uint64 => address) public approvedSenders; // chainSelector -> approved sender address
    mapping(uint256 => function(bytes calldata) external) public functionRoutes;
    address public individualManager;
    uint64 public immutable arbitrumChainSelector;

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    event SenderApproved(uint64 indexed chainSelector, address indexed sender);
    event FunctionExecuted(uint256 indexed functionId, address indexed caller, bool success);
    event FunctionRouteUpdated(uint256 indexed functionId, address indexed targetContract);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _individualManager, uint64 _arbitrumChainSelector) {
        individualManager = _individualManager;
        arbitrumChainSelector = _arbitrumChainSelector;
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Approves a single sender contract per chain selector.
     * @param chainSelector The chain ID from which the sender originates.
     * @param sender The only allowed sender contract from that chain.
     */
    function updateApprovedSender(uint64 chainSelector, address sender) external onlyOwner {
        approvedSenders[chainSelector] = sender;
        emit SenderApproved(chainSelector, sender);
    }

    /**
     * @notice Maps a function ID to a contract function selector.
     * @param functionId The ID representing the function to call.
     * @param target The contract function selector to execute.
     */
    function updateFunctionRoute(uint256 functionId, function(bytes calldata) external target) external onlyOwner {
        functionRoutes[functionId] = target;
        emit FunctionRouteUpdated(functionId, address(target));
    }

    /*//////////////////////////////////////////////////////////////
                          MESSAGE HANDLING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Handles incoming CCIP messages, verifies sender authenticity, and routes function calls.
     * @param any2EvmMessage The incoming CCIP message structure.
     */
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        uint64 sourceChain = any2EvmMessage.sourceChainSelector;
        address sender = abi.decode(any2EvmMessage.sender, (address));
        bytes memory data = any2EvmMessage.data;

        require(approvedSenders[sourceChain] == sender, "Unauthorized sender for this chain");

        (uint256 functionId, address caller, bytes memory parameters) = abi.decode(data, (uint256, address, bytes));

        function(bytes calldata) external targetFunction = functionRoutes[functionId];
        require(targetFunction != address(0), "Invalid function");

        (bool success, ) = address(targetFunction).call(parameters);
        emit FunctionExecuted(functionId, caller, success);
    }

    /**
     * @notice Allows direct calls from Arbitrum, bypassing CCIP fees.
     * @param functionId The ID representing the function to call.
     * @param parameters The encoded parameters for the function.
     */
    function localCall(uint256 functionId, bytes calldata parameters) external {
        require(block.chainid == arbitrumChainSelector, "Local call not allowed on this chain");

        function(bytes calldata) external targetFunction = functionRoutes[functionId];
        require(targetFunction != address(0), "Invalid function");

        (bool success, ) = address(targetFunction).call(parameters);
        emit FunctionExecuted(functionId, msg.sender, success);
    }
}
