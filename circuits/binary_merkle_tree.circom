// Refer to:
// https://github.com/appliedzkp/maci/blob/master/circuits/circom/trees/incrementalMerkleTree.circom

include "../node_modules/circomlib/circuits/mux1.circom";
include "../node_modules/circomlib/circuits/poseidon.circom";

template HashLeftRight() {
  signal input left;
  signal input right;

  signal output hash;

  component hasher = Poseidon(2);
  left ==> hasher.inputs[0];
  right ==> hasher.inputs[1];

  hash <== hasher.out;
}

template CalculateRootFromMerklePath(n_levels) {
    signal input leaf;
    signal input path_index[n_levels];
    signal input path_elements[n_levels][1];
    signal output root;

    component hashers[n_levels];
    component mux[n_levels];

    signal levelHashes[n_levels + 1];
    levelHashes[0] <== leaf;

    for (var i = 0; i < n_levels; i++) {
        // Should be 0 or 1
        path_index[i] * (1 - path_index[i]) === 0;

        hashers[i] = HashLeftRight();
        mux[i] = MultiMux1(2);

        mux[i].c[0][0] <== levelHashes[i];
        mux[i].c[0][1] <== path_elements[i][0];

        mux[i].c[1][0] <== path_elements[i][0];
        mux[i].c[1][1] <== levelHashes[i];

        mux[i].s <== path_index[i];
        hashers[i].left <== mux[i].out[0];
        hashers[i].right <== mux[i].out[1];

        levelHashes[i + 1] <== hashers[i].hash;
    }

    root <== levelHashes[n_levels];
}

template CheckLeafExists(levels){
  // Ensures that a leaf exists within a merkletree with given `root`

  // levels is depth of tree
  signal input leaf;

  signal private input path_elements[levels][1];
  signal private input path_index[levels];

  signal input root;

  component merkletree = CalculateRootFromMerklePath(levels);
  merkletree.leaf <== leaf;
  for (var i = 0; i < levels; i++) {
    merkletree.path_index[i] <== path_index[i];
    merkletree.path_elements[i][0] <== path_elements[i][0];
  }

  root === merkletree.root;
}

template CheckLeafUpdate(levels) {
  signal input oldLeaf;
  signal input newLeaf;
  signal private input path_elements[levels][1];
  signal private input path_index[levels];
  signal input oldRoot;
  signal input newRoot;
  component oldTree = CheckLeafExists(levels);
  oldTree.leaf <== oldLeaf;
  // we should implement batch signal assign & constrain later, to avoid the boilerplate code
  for (var i = 0; i < levels; i++) {
    oldTree.path_index[i] <== path_index[i];
    oldTree.path_elements[i][0] <== path_elements[i][0];
  }
  oldTree.root <== oldRoot;
  component newTree = CheckLeafExists(levels);
  newTree.leaf <== newLeaf;
  for (var i = 0; i < levels; i++) {
    newTree.path_index[i] <== path_index[i];
    newTree.path_elements[i][0] <== path_elements[i][0];
  }
  newTree.root <== newRoot;
}

template CalculateRootFromLeaves(levels) {
    // Given a Merkle root and a list of leaves, check if the root is the
    // correct result of inserting all the leaves into the tree (in the given
    // order)

    // Circom has some perticularities which limit the code patterns we can
    // use.

    // You can only assign a value to a signal once.

    // A component's input signal must only be wired to another component's output
    // signal.

    // Variables are only used for loops, declaring sizes of things, and anything
    // that is not related to inputs of a circuit.

    // The total number of leaves
    var totalLeaves = 2 ** levels;

    // The number of HashLeftRight components which will be used to hash the
    // leaves
    var numLeafHashers = totalLeaves / 2;

    // The number of HashLeftRight components which will be used to hash the
    // output of the leaf hasher components
    var numIntermediateHashers = numLeafHashers - 1;

    // Inputs to the snark
    signal private input leaves[totalLeaves];

    // The output
    signal output root;

    // The total number of hashers
    var numHashers = totalLeaves - 1;
    component hashers[numHashers];

    // Instantiate all hashers
    var i;
    for (i=0; i < numHashers; i++) {
        hashers[i] = HashLeftRight();
    }

    // Wire the leaf values into the leaf hashers
    for (i=0; i < numLeafHashers; i++){
        hashers[i].left <== leaves[i*2];
        hashers[i].right <== leaves[i*2+1];
    }

    // Wire the outputs of the leaf hashers to the intermediate hasher inputs
    var k = 0;
    for (i=numLeafHashers; i<numLeafHashers + numIntermediateHashers; i++) {
        hashers[i].left <== hashers[k*2].hash;
        hashers[i].right <== hashers[k*2+1].hash;
        k++;
    }

    // Wire the output of the final hash to this circuit's output
    root <== hashers[numHashers-1].hash;
}
