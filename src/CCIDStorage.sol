// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import {StorageSender} from "./StorageSender.sol";

/**
 * @title CCIDStorage
 * @notice Stores CCID membership data and triggers cross-chain updates via StorageSender.
 */
contract CCIDStorage is Ownable {
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

    struct CommunityCCID {
        address creator;
        uint256 totalMembers;
        mapping(uint256 => bytes32) members;
        mapping(bytes32 => uint256) ccidToIndex;
    }

    // Storage for Individuals & Communities
    mapping(bytes32 => IndividualCCID) private individuals;
    mapping(bytes32 => CommunityCCID) private communities;
    mapping(bytes32 => bytes32) public addressToCCID;

    // Allowed contracts for modifying data
    address public individualManager;
    address public communityManager;
    address public storageSender;

    uint256 public totalCCIDs; // 🔹 Track the number of CCIDs created

    /*//////////////////////////////////////////////////////////////
                           EVENTS
    //////////////////////////////////////////////////////////////*/

    event IndividualCreated(bytes32 indexed ccid, address indexed creator);
    event CommunityCreated(bytes32 indexed ccid, address indexed creator);
    event AddressLinked(bytes32 indexed ccid, uint256 chainId, address indexed linkedAddress);
    event AddressUnlinked(bytes32 indexed ccid, uint256 chainId, address indexed linkedAddress);
    event CommunityMemberAdded(bytes32 indexed communityCCID, bytes32 indexed memberCCID);
    event CommunityMemberRemoved(bytes32 indexed communityCCID, bytes32 indexed memberCCID);
    event ManagersUpdated(address indexed newIndividualManager, address indexed newCommunityManager);
    event StorageSenderUpdated(address indexed newStorageSender);

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                      MODIFIERS & ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    modifier onlyIndividualManager() {
        require(msg.sender == individualManager, "Unauthorized: Not Individual Manager");
        _;
    }

    modifier onlyCommunityManager() {
        require(msg.sender == communityManager, "Unauthorized: Not Community Manager");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function updateManagers(address _individualManager, address _communityManager) external onlyOwner {
        individualManager = _individualManager;
        communityManager = _communityManager;
        emit ManagersUpdated(_individualManager, _communityManager);
    }

    function updateStorageSender(address _storageSender) external onlyOwner {
        storageSender = _storageSender;
        emit StorageSenderUpdated(_storageSender);
    }

    /*//////////////////////////////////////////////////////////////
                      INDIVIDUAL CCID MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new Individual CCID with a **unique auto-generated ID**.
     * @param creator The creator of the CCID.
     * @return ccid The newly created CCID.
     */
    function createIndividualCCID(address creator) external onlyIndividualManager returns (bytes32 ccid) {
        totalCCIDs++;
        ccid = keccak256(abi.encodePacked(block.timestamp, creator, totalCCIDs)); // 🔹 Auto-generate unique CCID

        require(individuals[ccid].totalAddresses == 0, "CCID already exists");

        individuals[ccid].creator = creator;
        individuals[ccid].totalAddresses = 1;
        individuals[ccid].addresses[0] = ChainAddress(block.chainid, creator);
        individuals[ccid].addressToIndex[_makeAddressKey(block.chainid, creator)] = 0;

        emit IndividualCreated(ccid, creator);

        // 🔹 Send Storage Update Across Chains
        StorageSender(storageSender).sendStorageUpdate(
            ccid, block.chainid, creator, true, creator
        );
    }

    function linkAddress(bytes32 ccid, uint256 chainId, address linkedAddress) external onlyIndividualManager {
        IndividualCCID storage identity = individuals[ccid];

        bytes32 addrKey = _makeAddressKey(chainId, linkedAddress);
        require(identity.addressToIndex[addrKey] == 0, "Address already linked");

        uint256 index = identity.totalAddresses;
        identity.addresses[index] = ChainAddress(chainId, linkedAddress);
        identity.addressToIndex[addrKey] = index;
        identity.totalAddresses++;

        addressToCCID[addrKey] = ccid;
        emit AddressLinked(ccid, chainId, linkedAddress);

        // 🔹 Send Storage Update Across Chains
        StorageSender(storageSender).sendStorageUpdate(
            ccid, chainId, linkedAddress, true, identity.creator
        );
    }

    function unlinkAddress(bytes32 ccid, uint256 chainId, address linkedAddress) external onlyIndividualManager {
    IndividualCCID storage identity = individuals[ccid];

    bytes32 addrKey = _makeAddressKey(chainId, linkedAddress);
    uint256 index = identity.addressToIndex[addrKey];
    
    require(index != 0, "Address not linked");  // 🔹 Ensure the address is actually linked
    require(linkedAddress != identity.creator, "Cannot remove creator"); // 🔹 Prevent creator removal

    uint256 lastIndex = identity.totalAddresses - 1;

    if (index != lastIndex) {
        // 🔹 Swap with the last entry before deleting to maintain a compact structure
        ChainAddress storage lastAddress = identity.addresses[lastIndex];
        identity.addresses[index] = lastAddress;
        identity.addressToIndex[_makeAddressKey(lastAddress.chainId, lastAddress.addr)] = index;
    }

    // 🔹 Delete the last index
    delete identity.addresses[lastIndex];
    delete identity.addressToIndex[addrKey];
    delete addressToCCID[addrKey];
    identity.totalAddresses--;

    emit AddressUnlinked(ccid, chainId, linkedAddress);

    // 🔹 Send Storage Update Across Chains
    StorageSender(storageSender).sendStorageUpdate(
        ccid, chainId, linkedAddress, false, identity.creator
    );
}


    /*//////////////////////////////////////////////////////////////
                      VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getCCIDForAddress(uint256 chainId, address addr) external view returns (bytes32) {
        return addressToCCID[_makeAddressKey(chainId, addr)];
    }

    function _makeAddressKey(uint256 chainId, address addr) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(chainId, addr));
    }

    function getCCIDCreator(bytes32 ccid) external view returns (address) {
        return individuals[ccid].creator;
    }
}
