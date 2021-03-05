// original: https://github.com/tornadocash/tornado-core/blob/77af0c5bddfcf9d973efbc38278a249bb0173da3/contracts/MerkleTreeWithHistory.sol

pragma solidity ^0.7.0;

library Hasher {
  function MiMCSponge(uint256 L, uint256 R) public pure returns (uint256 xL, uint256 xR);
}

contract CachedMerkleTree {
  uint256 public constant FIELD_SIZE = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
  // keccak256("webb") % FIELD_SIZE
  uint256 public constant ZERO_VALUE = 14592352227349496974679011168619727440163368453936931423676065614125699432448;

  uint8 public depth;

  // the following variables are made public for easier testing and debugging and
  // are not supposed to be accessed in regular code
  bytes32[] public filledSubtrees;
  bytes32[] public zeros;
  uint32 public currentRootIndex = 0;
  uint32 public nextIndex = 0;

  uint8 public constant ROOT_HISTORY_SIZE = 100;
  bytes32[ROOT_HISTORY_SIZE] public roots;

  constructor(uint8 _depth) public {
    require(_depth > 0, "_depth should be greater than zero");
    require(_depth < 32, "_depth should be less than 32");
    depth = _depth;

    // local mutable (in the loop)
    bytes32 currentZero = bytes32(ZERO_VALUE);
    zeros.push(currentZero);
    filledSubtrees.push(currentZero);

    for (uint32 i = 1; i < depth; i++) {
      currentZero = hashLeftRight(currentZero, currentZero);
      zeros.push(currentZero);
      filledSubtrees.push(currentZero);
    }

    roots[0] = hashLeftRight(currentZero, currentZero);
  }

  /**
    @dev Hash 2 tree leaves, returns MiMC(_left, _right)
  */
  function hashLeftRight(bytes32 _left, bytes32 _right) public pure returns (bytes32) {
    require(uint256(_left) < FIELD_SIZE, "_left should be inside the field");
    require(uint256(_right) < FIELD_SIZE, "_right should be inside the field");
    uint256 R = uint256(_left);
    uint256 C = 0;
    (R, C) = Hasher.MiMCSponge(R, C);
    R = addmod(R, uint256(_right), FIELD_SIZE);
    (R, C) = Hasher.MiMCSponge(R, C);
    return bytes32(R);
  }

  function _insert(bytes32 _leaf) internal returns(uint32 index) {
    uint32 currentIndex = nextIndex;
    require(currentIndex != uint32(2)**depth, "Merkle tree is full. No more leafs can be added");
    nextIndex += 1;
    bytes32 currentLevelHash = _leaf;
    bytes32 left;
    bytes32 right;

    for (uint32 i = 0; i < depth; i++) {
      bool isLeft = currentIndex % 2 == 0;
      if (isLeft) {
        left = currentLevelHash;
        right = zeros[i];
        filledSubtrees[i] = currentLevelHash;
      } else {
        left = filledSubtrees[i];
        right = currentLevelHash;
      }
      currentLevelHash = hashLeftRight(left, right);
      currentIndex /= 2;
    }

    currentRootIndex = (currentRootIndex + 1) % ROOT_HISTORY_SIZE;
    roots[currentRootIndex] = currentLevelHash;
    return nextIndex - 1;
  }

  function isKnownRoot(bytes32 memory _root) public view returns(bool) {
    if (_root == 0) {
      return false;
    }
    // the way we try to find the root here is the most efficient way
    // this because we 99% of the time this will return true, we will check with a recent
    // root, so it would be good to always start searching from the last known root index and go back.
    //
    // we first start searching from the currentRootIndex we know.
    uint32 i = currentRootIndex;
    do {
      // then if we check if we found it? if so we return immediatly.
      if (_root == roots[i]) {
        return true;
      }
      // skip this and read the following comment for now.
      // ~ ~ ~ ~
      // and here we check if we reached the head, if so we return back to the end = ROOT_HISTORY_SIZE.
      if (i == 0) {
        i = ROOT_HISTORY_SIZE;
      }
      // if we did not found it, we go back one cell.
      i--;
    } while (i != currentRootIndex);
    return false;
  }

  function getLastRoot() public view returns(bytes32) {
    return roots[currentRootIndex];
  }
}
