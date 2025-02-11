// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title IndividualSender
 * @notice Sends CCIP messages to Arbitrum with EIP-712 signature verification.
 */
contract IndividualSender is Ownable, EIP712 {
    using ECDSA for bytes32;

    address public immutable router;
    address public immutable linkToken;
    uint64 public immutable arbitrumChainSelector;
    address public receiverContract;

    string private constant SIGNING_DOMAIN = "CCIDIndividualManager";
    string private constant SIGNATURE_VERSION = "1";

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    event ReceiverUpdated(address indexed newReceiver);
    event MessageSent(bytes32 indexed messageId, uint256 indexed functionId, address indexed sender);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _router,
        address _linkToken,
        uint64 _arbitrumChainSelector,
        address _receiverContract
    ) Ownable(msg.sender) EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) {
        router = _router;
        linkToken = _linkToken;
        arbitrumChainSelector = _arbitrumChainSelector;
        receiverContract = _receiverContract;
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function updateReceiver(address _receiverContract) external onlyOwner {
        receiverContract = _receiverContract;
        emit ReceiverUpdated(_receiverContract);
    }

    /*//////////////////////////////////////////////////////////////
                     CROSS-CHAIN CCID OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function linkAddress(
        bytes32 ccid,
        uint256 chainId,
        address linkedAddress,
        bytes memory signature
    ) external payable {
        _verifySignature(ccid, chainId, linkedAddress, signature);
        _sendCCIPMessage(1, abi.encode(ccid, msg.sender, chainId, linkedAddress));
    }

    function unlinkAddress(
        bytes32 ccid,
        uint256 chainId,
        address linkedAddress,
        bytes memory signature
    ) external payable {
        _verifySignature(ccid, chainId, linkedAddress, signature);
        _sendCCIPMessage(2, abi.encode(ccid, msg.sender, chainId, linkedAddress));
    }

    function approveAddress(
        bytes32 ccid,
        address newAddress,
        bytes memory signature
    ) external payable {
        _verifySignature(ccid, newAddress, signature);
        _sendCCIPMessage(3, abi.encode(ccid, msg.sender, newAddress));
    }

    function revokeAddress(
        bytes32 ccid,
        address targetAddress,
        bytes memory signature
    ) external payable {
        _verifySignature(ccid, targetAddress, signature);
        _sendCCIPMessage(4, abi.encode(ccid, msg.sender, targetAddress));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _verifySignature(
        bytes32 ccid,
        uint256 chainId,
        address addr,
        bytes memory signature
    ) internal view {
        bytes32 structHash = keccak256(abi.encode(ccid, chainId, addr));
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);
        require(signer == msg.sender, "Invalid signature");
    }

    // Overloaded function for approve/revoke
    function _verifySignature(
        bytes32 ccid,
        address addr,
        bytes memory signature
    ) internal view {
        bytes32 structHash = keccak256(abi.encode(ccid, addr));
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);
        require(signer == msg.sender, "Invalid signature");
    }

    function _sendCCIPMessage(uint256 functionId, bytes memory parameters) internal {
        bytes memory data = abi.encode(functionId, msg.sender, parameters);
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverContract),
            data: data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: 200_000, allowOutOfOrderExecution: true})),
            feeToken: linkToken
        });

        uint256 fee = IRouterClient(router).getFee(arbitrumChainSelector, message);

        LinkTokenInterface(linkToken).approve(router, fee);
        bytes32 messageId = IRouterClient(router).ccipSend(arbitrumChainSelector, message);

        emit MessageSent(messageId, functionId, msg.sender);
    }
}
