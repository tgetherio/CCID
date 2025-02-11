// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CCIDIndividualManager} from "./CCIDIndividualManager.sol";

/**
 * @title CCIDReceiver
 * @notice Receives CCIP messages, verifies sender authenticity, and routes function calls.
 */
contract CCIDReceiver is CCIPReceiver, Ownable {
    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    mapping(uint64 => address) public approvedSenders; // chainSelector -> approved sender address
    address public individualManager;
    uint64 public immutable arbitrumChainSelector;

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    event SenderApproved(uint64 indexed chainSelector, address indexed sender);
    event FunctionExecuted(uint256 indexed functionId, address indexed caller, bool success);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _router, address _individualManager, uint64 _arbitrumChainSelector)
        Ownable(msg.sender)
        CCIPReceiver(_router)
    {
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

    /*//////////////////////////////////////////////////////////////
                          MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Ensures the sender is an approved CCIP sender from the correct chain.
     */
    modifier onlyApprovedSender(uint64 sourceChain, address sender) {
        require(approvedSenders[sourceChain] == sender, "Unauthorized sender for this chain");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                          MESSAGE HANDLING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Handles incoming CCIP messages, verifies sender authenticity, and routes function calls.
     * @param any2EvmMessage The incoming CCIP message structure.
     */
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage)
        internal
        override
        onlyApprovedSender(any2EvmMessage.sourceChainSelector, abi.decode(any2EvmMessage.sender, (address)))
    {
        (uint256 functionId, address caller, bytes memory parameters) = abi.decode(any2EvmMessage.data, (uint256, address, bytes));

        bool success = false;
        if (functionId == 1) {
            success = _handleLinkAddress(parameters);
        } else if (functionId == 2) {
            success = _handleUnlinkAddress(parameters);
        } else if (functionId == 3) {
            success = _handleApproveAddress(parameters);
        } else if (functionId == 4) {
            success = _handleRevokeAddress(parameters);
        } else {
            revert("Invalid function ID");
        }

        emit FunctionExecuted(functionId, caller, success);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL HANDLERS
    //////////////////////////////////////////////////////////////*/

    function _handleLinkAddress(bytes memory parameters) internal returns (bool) {
        (bytes32 ccid, , uint256 chainId, address linkedAddress) =
            abi.decode(parameters, (bytes32, address, uint256, address));

        CCIDIndividualManager(individualManager).linkAddressFromReceiver(ccid, chainId, linkedAddress);
        return true;
    }

    function _handleUnlinkAddress(bytes memory parameters) internal returns (bool) {
        (bytes32 ccid, , uint256 chainId, address linkedAddress) =
            abi.decode(parameters, (bytes32, address, uint256, address));

        CCIDIndividualManager(individualManager).unlinkAddressFromReceiver(ccid, chainId, linkedAddress);
        return true;
    }

    function _handleApproveAddress(bytes memory parameters) internal returns (bool) {
        (bytes32 ccid, address caller, address approvedAddress) =
            abi.decode(parameters, (bytes32, address, address));

        CCIDIndividualManager(individualManager).approveAddressFromReceiver(ccid, caller, approvedAddress);
        return true;
    }

    function _handleRevokeAddress(bytes memory parameters) internal returns (bool) {
        (bytes32 ccid, address caller, address revokedAddress) =
            abi.decode(parameters, (bytes32, address, address));

        CCIDIndividualManager(individualManager).revokeAddressFromReceiver(ccid, caller, revokedAddress);
        return true;
    }

}
