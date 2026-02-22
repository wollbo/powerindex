// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract RequestRegistry {
    enum Status {
        None,
        Pending,
        Fulfilled,
        Cancelled,
        Expired
    }

    struct Request {
        // Request key
        bytes32 indexId;
        bytes32 areaId;
        uint32 yyyymmdd;
        string currency;

        // Lifecycle
        uint64 createdAt;
        Status status;

        // Fulfillment info (for UI / audit)
        int256 value1e6;
        bytes32 datasetHash;
        uint64 fulfilledAt;
    }

    address public owner;
    address public fulfiller;
    address public immutable consumer;

    uint256 public nextRequestId;
    mapping(uint256 => Request) public requests;

    error NotOwner();
    error NotFulfiller();
    error InvalidStatus();
    error ZeroAddress();

    event RequestCreated(
        uint256 indexed requestId,
        bytes32 indexed indexId,
        bytes32 indexed areaId,
        uint32 yyyymmdd,
        string currency,
        address consumer
    );

    event RequestFulfilled(
        uint256 indexed requestId,
        int256 value1e6,
        bytes32 datasetHash,
        uint64 fulfilledAt
    );

    event RequestCancelled(uint256 indexed requestId);

    constructor(address fulfiller_, address consumer_) {
        if (fulfiller_ == address(0) || consumer_ == address(0)) revert ZeroAddress();
        owner = msg.sender;
        fulfiller = fulfiller_;
        consumer = consumer_;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyFulfiller() {
        if (msg.sender != fulfiller) revert NotFulfiller();
        _;
    }

    function createRequest(
        bytes32 indexId,
        bytes32 areaId,
        uint32 yyyymmdd,
        string calldata currency
    ) external onlyOwner returns (uint256 requestId) {
        requestId = nextRequestId++;

        requests[requestId] = Request({
            indexId: indexId,
            areaId: areaId,
            yyyymmdd: yyyymmdd,
            currency: currency,
            createdAt: uint64(block.timestamp),
            status: Status.Pending,
            value1e6: 0,
            datasetHash: bytes32(0),
            fulfilledAt: 0
        });

        emit RequestCreated(requestId, indexId, areaId, yyyymmdd, currency, consumer);
    }

    function markFulfilled(
        uint256 requestId,
        int256 value1e6,
        bytes32 datasetHash
    ) external onlyFulfiller {
        Request storage r = requests[requestId];
        if (r.status != Status.Pending) revert InvalidStatus();

        r.status = Status.Fulfilled;
        r.value1e6 = value1e6;
        r.datasetHash = datasetHash;
        r.fulfilledAt = uint64(block.timestamp);

        emit RequestFulfilled(requestId, value1e6, datasetHash, r.fulfilledAt);
    }

    function cancelRequest(uint256 requestId) external onlyOwner {
        Request storage r = requests[requestId];
        if (r.status != Status.Pending) revert InvalidStatus();

        r.status = Status.Cancelled;
        emit RequestCancelled(requestId);
    }

}
