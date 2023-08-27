// Based on https://github.com/Dev43/heap-solidity/blob/master/contracts/Heap.sol
module interest_lsd::heap {
  
  use sui::object::{Self, UID};
  use sui::dynamic_field as field;
  use sui::tx_context::TxContext;

  const MAX_INDEX: u64 = 1;

  const ERROR_EMPTY_HEAP: u64 = 0;

  struct Heap<phantom T: store> has key, store {
    id: UID,
    size: u64
  }

  struct Node<T: store> has store {
    value: u64,
    data: T
  }

  public fun new<T: store>(ctx: &mut TxContext): Heap<T> {
    Heap {
      id: object::new(ctx),
      size: 1,
    }
  }

  public fun length<T: store>(heap: &Heap<T>): u64 {
    heap.size
  }

  public fun insert<T: store>(
    heap: &mut Heap<T>,
    value: u64,
    data: T,
  ) {
    let current_index = heap.size;

    field::add(&mut heap.id, current_index, Node { value, data });
    heap.size = current_index + 1;

    let parent_value = field::borrow_mut<u64, Node<T>>(&mut heap.id, (current_index / 2)).value;
    let current_value = value;

    // If there is more than 1 value in our heap and current is bigger than the current we swap them
    while (current_index > 1 && parent_value < current_value) {

      let parent_index = current_index / 2;

      let parent = field::remove<u64, Node<T>>(&mut heap.id, parent_index);
      let current = field::remove<u64, Node<T>>(&mut heap.id, current_index);

      field::add(&mut heap.id, parent_index, current);
      field::add(&mut heap.id, current_index, parent);

      // Move up to parent
      current_index = current_index / 2;
    };
  }

  public fun borrow_max<T: store>(heap: &Heap<T>): &Node<T> {
    field::borrow<u64, Node<T>>(&heap.id, MAX_INDEX)
  }

  public fun is_empty<T: store>(heap: &Heap<T>): bool {
    heap.size == 1
  }

  public fun remove_max<T: store>(heap: &mut Heap<T>): Node<T> {
    assert!(heap.size > 1, ERROR_EMPTY_HEAP);

    let max = field::remove<u64, Node<T>>(&mut heap.id, MAX_INDEX);

    let last_element = field::remove<u64, Node<T>>(&mut heap.id, heap.size - 1);
    field::add(&mut heap.id, 1, last_element);

    heap.size = heap.size - 1;

    // Start at the top
    let current_index = 1;

    while (current_index * 2 < heap.size - 1) {
      let j = current_index * 2;

      let left_child_value = field::borrow<u64, Node<T>>(&heap.id, j).value;
      let right_child_value = field::borrow<u64, Node<T>>(&heap.id, j + 1).value;

      let greatest_value = if (left_child_value > right_child_value) { left_child_value } else { right_child_value };

      if (left_child_value < right_child_value) {
        j = j + 1;
      };

      if (field::borrow<u64, Node<T>>(&heap.id, current_index).value > greatest_value) break;

      let current = field::remove<u64, Node<T>>(&mut heap.id, current_index);
      let j_node = field::remove<u64, Node<T>>(&mut heap.id, j);

      field::add(&mut heap.id, j, current);
      field::add(&mut heap.id, current_index, j_node);

      current_index = j;
    };

    max
  }

}