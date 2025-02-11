// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title StorageReceiver
 * @notice Receives CCID storage updates from StorageSender.sol and stores them locally.
 */
contract StorageReceiver is CCIPReceiver, Ownable {
    enum CCIDType { INDIVIDUAL, COMMUNITY }

    struct ChainAddress {
        uint256 chainId;
        address addr;
    }

    struct IndividualCCID {
        address creator;
        uint256 totalAddresses;
        mapping(uint256 => ChainAddress) addresses;
        mapping(bytes32 => uint256) addressToIndex;
    }

    // Mapping: CCID => last update timestamp
    mapping(bytes32 => uint256) public lastUpdated; 

    // Storage for Individual CCIDs
    mapping(bytes32 => IndividualCCID) private individuals;
    mapping(bytes32 => bytes32) public addressToCCID; // keccak256(chainId, address) => ccid

    // Approved senders from different chains
    mapping(uint64 => address) public approvedSenders; 

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    event SenderApproved(uint64 indexed chainSelector, address indexed sender);
    event CCIDUpdated(bytes32 indexed ccid, uint256 chainId, address indexed linkedAddress, bool added, uint256 timestamp);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _router) CCIPReceiver(_router) Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Approves a sender contract per chain for receiving CCID updates.
     * @param chainSelector The chain ID from which the sender originates.
     * @param sender The only allowed sender contract from that chain.
     */
    function approveSender(uint64 chainSelector, address sender) external onlyOwner {
        approvedSenders[chainSelector] = sender;
        emit SenderApproved(chainSelector, sender);
    }

    /*//////////////////////////////////////////////////////////////
                          MESSAGE HANDLING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Handles incoming CCIP messages and updates CCID storage.
     * @param any2EvmMessage The incoming CCIP message structure.
     */
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        uint64 sourceChain = any2EvmMessage.sourceChainSelector;
        address sender = abi.decode(any2EvmMessage.sender, (address));
        require(approvedSenders[sourceChain] == sender, "Unauthorized sender");

        (bytes32 ccid, uint256 chainId, address linkedAddress, bool added, address creator, uint256 timestamp) = 
            abi.decode(any2EvmMessage.data, (bytes32, uint256, address, bool, address, uint256));

        // Ensure we only apply newer updates
        require(timestamp > lastUpdated[ccid], "Received outdated CCID update");

        if (added) {
            _addAddress(ccid, chainId, linkedAddress, creator);
        } else {
            _removeAddress(ccid, chainId, linkedAddress);
        }

        lastUpdated[ccid] = timestamp;
        emit CCIDUpdated(ccid, chainId, linkedAddress, added, timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL STORAGE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _addAddress(bytes32 ccid, uint256 chainId, address linkedAddress, address creator) internal {
        IndividualCCID storage identity = individuals[ccid];

        // If this is the first time seeing this CCID, store creator
        if (identity.creator == address(0)) {
            identity.creator = creator;
        }

        bytes32 addrKey = keccak256(abi.encodePacked(chainId, linkedAddress));
        require(identity.addressToIndex[addrKey] == 0, "Address already exists");

        uint256 index = identity.totalAddresses;
        identity.addresses[index] = ChainAddress(chainId, linkedAddress);
        identity.addressToIndex[addrKey] = index;
        identity.totalAddresses++;

        addressToCCID[addrKey] = ccid;
    }

    function _removeAddress(bytes32 ccid, uint256 chainId, address linkedAddress) internal {
        IndividualCCID storage identity = individuals[ccid];

        bytes32 addrKey = keccak256(abi.encodePacked(chainId, linkedAddress));
        uint256 index = identity.addressToIndex[addrKey];
        require(index != 0, "Address not found");

        uint256 lastIndex = identity.totalAddresses - 1;
        if (index != lastIndex) {
            ChainAddress storage lastAddress = identity.addresses[lastIndex];
            identity.addresses[index] = lastAddress;
            identity.addressToIndex[keccak256(abi.encodePacked(lastAddress.chainId, lastAddress.addr))] = index;
        }

        delete identity.addresses[lastIndex];
        delete identity.addressToIndex[addrKey];
        delete addressToCCID[addrKey];
        identity.totalAddresses--;
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns all linked addresses for a CCID.
     * @param ccid The CCID to query.
     * @return creator The CCID creator.
     * @return addresses Array of ChainAddress structs.
     */
    function getCCID(bytes32 ccid) external view returns (address creator, ChainAddress[] memory addresses) {
        IndividualCCID storage identity = individuals[ccid];
        creator = identity.creator;
        addresses = new ChainAddress[](identity.totalAddresses);

        for (uint256 i = 0; i < identity.totalAddresses; i++) {
            addresses[i] = identity.addresses[i];
        }
    }

    /**
     * @notice Checks if an address is linked to a CCID.
     * @param chainId The chain ID of the address.
     * @param addr The address to check.
     * @return ccid The CCID the address belongs to.
     */
    function getCCIDForAddress(uint256 chainId, address addr) external view returns (bytes32) {
        return addressToCCID[keccak256(abi.encodePacked(chainId, addr))];
    }
}
