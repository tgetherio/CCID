// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title StorageSender
 * @notice Sends CCID storage updates to all chains via CCIP.
 */
contract StorageSender is Ownable {
    enum PayFeesIn {
        Native,
        LINK
    }
    PayFeesIn payFeesIn = PayFeesIn.LINK;


    address public immutable router;
    address public immutable linkToken;
    address public ccidStorage; // 🔹 Allows `CCIDStorage.sol` to call this contract
    
    mapping(uint64 => address) public storageReceivers; // chainSelector -> approved storage receiver
    uint64[] public chainSelectors; // List of chains we need to send updates to

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    event StorageReceiverUpdated(uint64 indexed chainSelector, address indexed receiver);
    event StorageReceiverRemoved(uint64 indexed chainSelector);
    event StorageUpdateSent(
        bytes32 indexed ccid,
        uint256 chainId,
        address indexed linkedAddress,
        bool added,
        address creator,
        uint256 timestamp
    );

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _router, address _linkToken) Ownable(msg.sender) {
        router = _router;
        linkToken = _linkToken;
    }

    /*//////////////////////////////////////////////////////////////
                       CHAIN & CONTRACT MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows `CCIDStorage.sol` to call this contract.
     * @param _ccidStorage The storage contract address.
     */
    function setCCIDStorage(address _ccidStorage) external onlyOwner {
        require(_ccidStorage != address(0), "Invalid CCIDStorage address");
        ccidStorage = _ccidStorage;
    }

    /**
     * @notice Adds or updates a storage receiver for a specific chain.
     * @param chainSelector The chain ID (selector) of the destination chain.
     * @param receiver The contract address on that chain to receive updates.
     */
    function updateStorageReceiver(uint64 chainSelector, address receiver) external onlyOwner {
        require(receiver != address(0), "Invalid receiver address");

        if (storageReceivers[chainSelector] == address(0)) {
            // Add a new chain if it's not already tracked
            chainSelectors.push(chainSelector);
        }

        storageReceivers[chainSelector] = receiver;
        emit StorageReceiverUpdated(chainSelector, receiver);
    }

    /**
     * @notice Removes a storage receiver from the sync list.
     * @param chainSelector The chain ID (selector) to remove.
     */
    function removeStorageReceiver(uint64 chainSelector) external onlyOwner {
        require(storageReceivers[chainSelector] != address(0), "Chain not registered");

        delete storageReceivers[chainSelector];

        // Find and remove from `chainSelectors[]`
        for (uint256 i = 0; i < chainSelectors.length; i++) {
            if (chainSelectors[i] == chainSelector) {
                chainSelectors[i] = chainSelectors[chainSelectors.length - 1]; // Swap with last
                chainSelectors.pop(); // Remove last
                break;
            }
        }

        emit StorageReceiverRemoved(chainSelector);
    }

    /*//////////////////////////////////////////////////////////////
                         STORAGE UPDATE SENDER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sends CCID storage update to all approved chains.
     * @param ccid The CCID being updated.
     * @param chainId The chain ID of the updated address.
     * @param linkedAddress The address being added/removed.
     * @param added `true` if the address was added, `false` if removed.
     * @param creator The original creator of the CCID.
     */
    function sendStorageUpdate(
        bytes32 ccid,
        uint256 chainId,
        address linkedAddress,
        bool added,
        address creator
    ) external {
        require(msg.sender == ccidStorage, "Unauthorized: Only CCIDStorage can call");

        uint256 timestamp = block.timestamp;
        bytes memory data = abi.encode(ccid, chainId, linkedAddress, added, creator, timestamp);

        for (uint256 i = 0; i < chainSelectors.length; i++) {
            uint64 chainSelector = chainSelectors[i];
            address receiver = storageReceivers[chainSelector];

            require(receiver != address(0), "No receiver set for chain");

            Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
                receiver: abi.encode(receiver),
                data: data,
                tokenAmounts: new Client.EVMTokenAmount[](0),
                extraArgs: Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: 200_000, allowOutOfOrderExecution: true})),
                feeToken: payFeesIn == PayFeesIn.LINK ? linkToken : address(0)
            });

            uint256 fee = IRouterClient(router).getFee(chainSelector, message);

            if (payFeesIn == PayFeesIn.LINK) {
                LinkTokenInterface(linkToken).approve(router, fee);
                IRouterClient(router).ccipSend(chainSelector, message);
            } else {
                IRouterClient(router).ccipSend{value: fee}(chainSelector, message);
            }

            emit StorageUpdateSent(ccid, chainId, linkedAddress, added, creator, timestamp);
        }
    }
}
