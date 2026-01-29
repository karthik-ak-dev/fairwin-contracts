// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

/**
 * @title MockVRFCoordinator
 * @notice Mock Chainlink VRF Coordinator for testing
 */
contract MockVRFCoordinator is VRFCoordinatorV2Interface {
    uint256 private _requestId = 1;
    
    struct Request {
        address consumer;
        uint32 numWords;
        bool fulfilled;
    }
    
    mapping(uint256 => Request) public requests;
    
    function requestRandomWords(
        bytes32, // keyHash
        uint64, // subId
        uint16, // minimumRequestConfirmations
        uint32, // callbackGasLimit
        uint32 numWords
    ) external override returns (uint256 requestId) {
        requestId = _requestId++;
        requests[requestId] = Request({
            consumer: msg.sender,
            numWords: numWords,
            fulfilled: false
        });
        return requestId;
    }
    
    /**
     * @notice Manually fulfill a VRF request (for testing)
     * @param requestId The request ID to fulfill
     * @param consumer The consumer contract address
     * @param randomWords Array of random numbers
     */
    function fulfillRandomWords(
        uint256 requestId,
        address consumer,
        uint256[] memory randomWords
    ) external {
        Request storage request = requests[requestId];
        require(!request.fulfilled, "Already fulfilled");
        require(request.consumer == consumer, "Wrong consumer");
        
        request.fulfilled = true;
        
        // Call the consumer's fulfillRandomWords
        (bool success, ) = consumer.call(
            abi.encodeWithSignature(
                "rawFulfillRandomWords(uint256,uint256[])",
                requestId,
                randomWords
            )
        );
        require(success, "Callback failed");
    }
    
    /**
     * @notice Auto-fulfill with generated random numbers (convenience method)
     */
    function fulfillRandomWordsWithRandom(uint256 requestId, address consumer) external {
        Request storage request = requests[requestId];
        require(!request.fulfilled, "Already fulfilled");
        
        uint256[] memory randomWords = new uint256[](request.numWords);
        for (uint32 i = 0; i < request.numWords; i++) {
            randomWords[i] = uint256(keccak256(abi.encodePacked(
                block.timestamp,
                block.prevrandao,
                requestId,
                i
            )));
        }
        
        request.fulfilled = true;
        
        (bool success, ) = consumer.call(
            abi.encodeWithSignature(
                "rawFulfillRandomWords(uint256,uint256[])",
                requestId,
                randomWords
            )
        );
        require(success, "Callback failed");
    }
    
    // Required interface implementations (not used in testing)
    
    function getRequestConfig() external pure override returns (uint16, uint32, bytes32[] memory) {
        return (3, 500000, new bytes32[](0));
    }
    
    function createSubscription() external pure override returns (uint64) {
        return 1;
    }
    
    function getSubscription(uint64) external pure override returns (
        uint96 balance,
        uint64 reqCount,
        address owner,
        address[] memory consumers
    ) {
        return (0, 0, address(0), new address[](0));
    }
    
    function requestSubscriptionOwnerTransfer(uint64, address) external pure override {}
    function acceptSubscriptionOwnerTransfer(uint64) external pure override {}
    function addConsumer(uint64, address) external pure override {}
    function removeConsumer(uint64, address) external pure override {}
    function cancelSubscription(uint64, address) external pure override {}
    function pendingRequestExists(uint64) external pure override returns (bool) { return false; }
}
