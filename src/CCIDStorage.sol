// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CCIDStorage
 * @notice Stores CCID membership data. Only approved contracts can modify data.
 */
contract CCIDStorage is Ownable {
    enum CCIDType { INDIVIDUAL, COMMUNITY }

    struct ChainAddress {
        uint256 chainId;
        address addr;
    }

    struct IndividualCCID {
        address creator; // Cannot be removed (Index 0)
        uint256 totalAddresses; // Number of linked addresses
        mapping(uint256 => ChainAddress) addresses; // index => (chainId, address)
        mapping(bytes32 => uint256) addressToIndex; // (chainId, address) => index
    }

    struct CommunityCCID {
        address creator; // Cannot be removed (Index 0)
        uint256 totalMembers; // Number of linked members (CCIDs)
        mapping(uint256 => bytes32) members; // index => CCID
        mapping(bytes32 => uint256) ccidToIndex; // CCID => index
    }

    // Storage for Individuals & Communities
    mapping(bytes32 => IndividualCCID) private individuals;
    mapping(bytes32 => CommunityCCID) private communities;
    mapping(bytes32 => bytes32) public addressToCCID;

    // Allowed contracts for modifying data
    address public individualManager;
    address public communityManager;

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

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address initialOwner) Ownable(initialOwner) {}

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

    function updateManagers(address _individualManager, address _communityManager) external onlyOwner {
        individualManager = _individualManager;
        communityManager = _communityManager;
        emit ManagersUpdated(_individualManager, _communityManager);
    }

    /*//////////////////////////////////////////////////////////////
                      INDIVIDUAL CCID MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function createIndividualCCID(bytes32 ccid, address creator) external onlyIndividualManager {
        require(individuals[ccid].totalAddresses == 0, "CCID already exists");

        individuals[ccid].creator = creator;
        individuals[ccid].totalAddresses = 1;
        individuals[ccid].addresses[0] = ChainAddress(block.chainid, creator);
        individuals[ccid].addressToIndex[_makeAddressKey(block.chainid, creator)] = 0;

        emit IndividualCreated(ccid, creator);
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
    }

    function unlinkAddress(bytes32 ccid, uint256 chainId, address linkedAddress) external onlyIndividualManager {
        IndividualCCID storage identity = individuals[ccid];

        bytes32 addrKey = _makeAddressKey(chainId, linkedAddress);
        uint256 index = identity.addressToIndex[addrKey];
        require(index != 0, "Address not linked");
        require(linkedAddress != identity.creator, "Cannot remove creator");

        uint256 lastIndex = identity.totalAddresses - 1;
        if (index != lastIndex) {
            ChainAddress storage lastAddress = identity.addresses[lastIndex];
            identity.addresses[index] = lastAddress;
            identity.addressToIndex[_makeAddressKey(lastAddress.chainId, lastAddress.addr)] = index;
        }

        delete identity.addresses[lastIndex];
        delete identity.addressToIndex[addrKey];
        delete addressToCCID[addrKey];
        identity.totalAddresses--;

        emit AddressUnlinked(ccid, chainId, linkedAddress);
    }

    /*//////////////////////////////////////////////////////////////
                      COMMUNITY CCID MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function createCommunityCCID(bytes32 ccid, address creator) external onlyCommunityManager {
        require(communities[ccid].totalMembers == 0, "CCID already exists");

        communities[ccid].creator = creator;
        emit CommunityCreated(ccid, creator);
    }

    function addCommunityMember(bytes32 communityCCID, bytes32 memberCCID) external onlyCommunityManager {
        CommunityCCID storage community = communities[communityCCID];

        uint256 index = community.totalMembers;
        community.members[index] = memberCCID;
        community.ccidToIndex[memberCCID] = index;
        community.totalMembers++;

        emit CommunityMemberAdded(communityCCID, memberCCID);
    }

    function removeCommunityMember(bytes32 communityCCID, bytes32 memberCCID) external onlyCommunityManager {
        CommunityCCID storage community = communities[communityCCID];

        uint256 index = community.ccidToIndex[memberCCID];
        require(index != 0, "Member not found");

        uint256 lastIndex = community.totalMembers - 1;
        if (index != lastIndex) {
            bytes32 lastMember = community.members[lastIndex];
            community.members[index] = lastMember;
            community.ccidToIndex[lastMember] = index;
        }

        delete community.members[lastIndex];
        delete community.ccidToIndex[memberCCID];
        community.totalMembers--;

        emit CommunityMemberRemoved(communityCCID, memberCCID);
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
}
