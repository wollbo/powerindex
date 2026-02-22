// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {NorthpoleOption} from "./NorthpoleOption.sol";
import {IIndexConsumer} from "../interfaces/IIndexConsumer.sol";

contract NorthpoleOptionFactory {
    event OptionCreated(
        address indexed option,
        address indexed consumer,
        address indexed seller,
        bytes32 indexId,
        bytes32 areaId,
        uint32 yyyymmdd,
        int256 strike1e6,
        uint8 direction,
        uint256 premiumWei,
        uint256 payoutWei,
        uint64 buyDeadline
    );

    error InvalidValue();
    error IndexAlreadyPublished();

    function createOption(
        address consumer,
        bytes32 indexId,
        bytes32 areaId,
        uint32 yyyymmdd,
        int256 strike1e6,
        uint8 direction, // 0/1
        uint256 premiumWei,
        uint64 buyDeadline
    ) external payable returns (address option) {
        if (msg.value == 0) revert InvalidValue();

        // Optional: enforce “no listing after index published” at the venue level too.
        (,,, uint64 reportedAt) = IIndexConsumer(consumer).commitments(indexId, areaId, yyyymmdd);
        if (reportedAt != 0) revert IndexAlreadyPublished();

        option = address(
            new NorthpoleOption{value: msg.value}(
                consumer,
                msg.sender,
                indexId,
                areaId,
                yyyymmdd,
                strike1e6,
                NorthpoleOption.Direction(direction),
                premiumWei,
                buyDeadline
            )
        );

        emit OptionCreated(
            option,
            consumer,
            msg.sender,
            indexId,
            areaId,
            yyyymmdd,
            strike1e6,
            direction,
            premiumWei,
            msg.value,
            buyDeadline
        );
    }
}
