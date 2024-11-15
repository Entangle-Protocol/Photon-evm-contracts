//SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

/// @title A library for ordered list management
/// @notice This library provides structures and functions to manage ordered lists and their slots.
/// Each slot in an ordered list contains a key as an identifier for any object and its `uint256` value for sorting.
/// The key and value together constitute the `element` of the list.
/// The list can be initialized as either ascending or descending and can be used for managing the sorted order and
/// providing a sorted array of objects upon request.
/// The object's value can be set as a new `element` or just changed, but the `element` cannot be removed from the list.
/// If an increase or decrease in value changes the sort order, the `element` will be moved to a new position.
/// Finally, the user can obtain the list of `elements` in sorted order.
library OrderedListUINT {
    enum ListType {
        NotInited,
        Ascending,
        Descending
    }
    struct Element {
        bytes key;
        uint256 value;
    }
    struct Slot {
        uint16 next;
        uint16 prev;
        uint16 me;
        Element elem;
    }

    struct List {
        uint16 head;
        uint16 tail;
        ListType lt;
        Slot[] slots;
        mapping(bytes key => uint16) keyToIndex; // 0 - key does not exist, if > 0 - index in slots increased by 1
    }

    /// @notice Ensures that the list has been initialized before proceeding with the `init` function call
    modifier inited(List storage list) {
        require(list.lt != ListType.NotInited, "List not inited");
        _;
    }

    /// @notice Initializes the list with a specific ListType
    /// @param list The list to initialize
    /// @param _lt The type of the list (Ascending or Descending)
    function init(List storage list, ListType _lt) internal {
        list.lt = _lt;
    }

    /// @notice Retrieves a slot by its index, checking if the list is initialized
    /// @param list The list to retrieve the slot from
    /// @param index The index of the slot to retrieve
    /// @return The Slot at the specified index (or empty slot dummy) and a boolean indicating success
    function getSlot(
        List storage list,
        uint16 index
    ) internal view inited(list) returns (Slot memory, bool) {
        if (index == 0 || index > list.slots.length) {
            return (Slot(0, 0, 0, Element("", 0)), false);
        }
        return (list.slots[toSlotId(index)], true);
    }

    /// @notice Retrieves a storage reference to a slot by its index, checking if the list is initialized
    /// @param list The list to retrieve the slot from
    /// @param index The index of the slot to retrieve
    /// @return A storage reference to the Slot at the specified index
    function getSlotStorage(
        List storage list,
        uint16 index
    ) private view inited(list) returns (Slot storage) {
        return list.slots[toSlotId(index)];
    }

    /// @notice Converts an external slot index to an internal array index
    /// @param index The external index
    /// @return The internal array index
    function toSlotId(uint16 index) private pure returns (uint16) {
        return index - 1;
    }

    /// @notice Finds the new position index for a slot based on its value and whether it has increased
    /// @param list The list containing the slot
    /// @param from The starting position for the search
    /// @param value The new value of the slot
    /// @param increased A flag indicating whether the slot's value has increased to determine the search direction
    /// @return pos The index where the slot should be moved to
    function findNewPosIndex(
        List storage list,
        uint16 from,
        uint256 value,
        bool increased
    ) private view inited(list) returns (uint16 pos) {
        if (from == 0) {
            return from;
        }
        (Slot memory currSlot, bool success) = getSlot(list, from);
        require(success, "Slot `from` not found");
        Slot memory nextSlot;

        if (list.lt == ListType.Ascending) {
            if (increased) {
                // it can be new slot to head, so if we start from head - check head
                if (list.head == currSlot.me && currSlot.elem.value >= value) {
                    return 0;
                }
                // going to tail
                do {
                    (nextSlot, success) = getSlot(list, currSlot.next);
                    // if current are - tail, or we found
                    if (!success || (currSlot.elem.value <= value && nextSlot.elem.value > value)) {
                        return currSlot.me;
                    }
                    currSlot = nextSlot;
                } while (currSlot.me != 0);
            } else {
                if (value == 0) {
                    return 0;
                }
                // going to head
                do {
                    (nextSlot, success) = getSlot(list, currSlot.prev);
                    // if current are - head
                    if (!success) {
                        return 0;
                    }
                    // if we found
                    if (currSlot.elem.value >= value && nextSlot.elem.value < value) {
                        return nextSlot.me;
                    }
                    currSlot = nextSlot;
                } while (currSlot.me != 0);
            }
        } else {
            if (increased) {
                if (list.tail == currSlot.me && currSlot.elem.value >= value) {
                    return currSlot.me;
                }
                // go to head
                do {
                    (nextSlot, success) = getSlot(list, currSlot.prev);
                    if (!success) {
                        return 0;
                    }
                    if (currSlot.elem.value <= value && nextSlot.elem.value > value) {
                        return nextSlot.me;
                    }
                    currSlot = nextSlot;
                } while (currSlot.me != 0);
            } else {
                if (value == 0) {
                    return list.tail;
                }
                // go to tail
                do {
                    (nextSlot, success) = getSlot(list, currSlot.next);
                    if (!success || (currSlot.elem.value >= value && nextSlot.elem.value < value)) {
                        return currSlot.me;
                    }
                    currSlot = nextSlot;
                } while (currSlot.me != 0);
            }
        }
    }

    /// @notice Links a slot to the list at a specific position
    /// @param list The list to link the slot to
    /// @param pos The position to link the slot to; if 0, link to head
    /// @param slot The slot to link
    function link(List storage list, uint16 pos, Slot storage slot) private inited(list) {
        // head
        if (pos == 0) {
            if (list.head == 0) {
                list.head = list.tail = slot.me;
                slot.next = slot.prev = 0;
                return;
            } else {
                Slot storage headSlot = getSlotStorage(list, list.head);
                slot.next = headSlot.me;
                headSlot.prev = slot.me;
                list.head = slot.me;
                return;
            }
        } else {
            Slot storage prevSlot = getSlotStorage(list, pos);
            slot.next = prevSlot.next;
            prevSlot.next = slot.me;
            slot.prev = pos;
            if (slot.next != 0) {
                Slot storage nextSlot = getSlotStorage(list, slot.next);
                nextSlot.prev = slot.me;
            }
            if (prevSlot.me == list.tail) {
                list.tail = slot.me;
            }
        }
    }

    /// @notice Unlinks a slot from the list
    /// @param list The list to unlink the slot from
    /// @param slot The slot to unlink
    function unlink(List storage list, Slot storage slot) private inited(list) {
        require(slot.me != 0, "Invalid slot");
        if (slot.prev != 0) {
            Slot storage prevSlot = getSlotStorage(list, slot.prev);
            prevSlot.next = slot.next;
        }
        if (slot.next != 0) {
            Slot storage nextSlot = getSlotStorage(list, slot.next);
            nextSlot.prev = slot.prev;
        }
        if (list.tail == slot.me) {
            list.tail = slot.prev;
        }
        if (list.head == slot.me) {
            list.head = slot.next;
        }
        slot.next = 0;
        slot.prev = 0;
    }

    /// @notice Sets or updates the value of an element in the list, reordering the list as necessary
    /// @param list The list to update
    /// @param key The key of the element to set or update
    /// @param value The new value for the element
    function set(List storage list, bytes memory key, uint256 value) internal inited(list) {
        uint16 index = list.keyToIndex[key];
        if (index != 0) {
            Slot storage slot = getSlotStorage(list, index);
            if (value == slot.elem.value) {
                return;
            }
            bool increased = value > slot.elem.value;
            uint16 newPos = findNewPosIndex(list, slot.me, value, increased);
            slot.elem.value = value;
            if (newPos == slot.me || (newPos == 0 && slot.me == list.head)) {
                return;
            }
            unlink(list, slot);
            link(list, newPos, slot);
        } else {
            uint16 newIndex = uint16(list.slots.length + 1);
            list.slots.push(Slot(0, 0, newIndex, Element(key, value)));
            list.keyToIndex[key] = newIndex;
            Slot storage slot = getSlotStorage(list, newIndex);
            uint16 pos = findNewPosIndex(
                list,
                list.lt == ListType.Ascending ? list.head : list.tail,
                value,
                true
            );
            link(list, pos, slot);
        }
    }

    /// @notice Retrieves the value associated with a key in the list
    /// @param list The list to search
    /// @param key The key of the element to find
    /// @return The value of the element, or 0 if the key is not found
    function getValue(List storage list, bytes memory key) internal view returns (uint256) {
        uint16 index = list.keyToIndex[key];
        if (index == 0) {
            return 0;
        }

        (Slot memory slot, ) = getSlot(list, index);

        return slot.elem.value;
    }

    /// @notice Returns an array of all elements in the list
    /// @param list The list from which elements will be retrieved
    /// @return An array of all elements in the list
    function get(List storage list) internal view returns (Element[] memory) {
        if (list.head == 0) {
            return new Element[](0);
        }
        Element[] memory res = new Element[](list.slots.length);
        (Slot memory slot, ) = getSlot(list, list.head);
        uint i;
        bool success;
        do {
            res[i] = slot.elem;
            (slot, success) = getSlot(list, slot.next);
            unchecked {
                i++;
            }
        } while (success);
        return res;
    }

    /// @notice Returns an array of all elements in the list converted to addresses
    /// @param list The list from which elements will be retrieved
    /// @return An array of all elements in the list converted to addresses
    function getAsAddress(List storage list) internal view returns (address[] memory) {
        uint n = list.slots.length;
        if (list.head == 0 || n == 0) {
            return new address[](0);
        }
        address[] memory res = new address[](n);
        Slot memory slot;
        bool success;
        uint i;
        uint16 next = list.head;
        do {
            (slot, success) = getSlot(list, next);
            require(success, "Test: should always be true");
            next = slot.next;
            res[i] = abi.decode(slot.elem.key, (address));
            unchecked {
                i++;
            }
        } while (i < n);
        return res;
    }

    /// @notice Returns an array of elements in the list up to a specified maximum depth
    /// @param list The list from which elements will be retrieved
    /// @param maxDepth The maximum number of elements to retrieve
    /// @return An array of elements in the list up to the specified maximum depth
    function get(List storage list, uint16 maxDepth) internal view returns (Element[] memory) {
        if (list.head == 0) {
            return new Element[](0);
        }
        Element[] memory res = new Element[](
            maxDepth > list.slots.length ? list.slots.length : maxDepth
        );
        (Slot memory slot, ) = getSlot(list, list.head);
        uint i;
        bool success;
        do {
            res[i] = slot.elem;
            (slot, success) = getSlot(list, slot.next);
            unchecked {
                i++;
            }
        } while (success && i < maxDepth);
        return res;
    }

    /// @notice Retrieves all slots in the list
    /// @param list The list from which slots will be retrieved
    /// @return An array of all slots in the list
    function getSlots(List storage list) internal view returns (Slot[] memory) {
        return list.slots;
    }

    /// @notice Clears all elements and resets the list to its uninitialized state
    /// @param list The list to clear
    function clear(List storage list) internal inited(list) {
        uint16 i;
        for (i = 0; i < list.slots.length; i++) {
            delete list.keyToIndex[list.slots[i].elem.key];
        }
        delete list.slots;
        list.lt = ListType.NotInited;
        list.head = 0;
        list.tail = 0;
    }
}
