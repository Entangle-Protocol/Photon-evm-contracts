//SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

import "../lib/OrderedListUINT.sol";

contract OrderedListLibTest {
    using OrderedListUINT for OrderedListUINT.List;

    OrderedListUINT.List public listAscending;
    OrderedListUINT.List public listDescending;

    constructor() {
        listAscending.init(OrderedListUINT.ListType.Ascending);
        listDescending.init(OrderedListUINT.ListType.Descending);
    }

    function set(bytes calldata key, uint256 value) external {
        listAscending.set(key, value);
        listDescending.set(key, value);
    }


    function getValue(bytes calldata key) external view returns (uint256) {
        return listAscending.getValue(key);
    }

    function getAscendingSlots() external view returns (OrderedListUINT.Slot[] memory) {
        return listAscending.getSlots();
    }

    function getAscending() external view returns (OrderedListUINT.Element[] memory) {
        return listAscending.get();
    }

    function getDescendingSlots() external view returns (OrderedListUINT.Slot[] memory) {
        return listDescending.getSlots();
    }

    function getDescending() external view returns (OrderedListUINT.Element[] memory) {
        return listDescending.get();
    }

    function getAscendingNotView(uint16 n) external returns (OrderedListUINT.Element[] memory) {
        if (n == 0) {
            return listAscending.get();
        }
        return listAscending.get(n);
    }

    function getHeadTailSlots() external view returns (OrderedListUINT.Slot memory head, OrderedListUINT.Slot memory tail) {
        (head,) = listAscending.getSlot(listAscending.head);
        (tail,) = listAscending.getSlot(listAscending.tail);
    }

    function clear() external {
        listAscending.clear();
        listDescending.clear();
    }
}
