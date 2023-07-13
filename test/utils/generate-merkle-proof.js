const fs = require("fs");
const path = require("path");
const { StandardMerkleTree } = require("@openzeppelin/merkle-tree");
const { defaultAbiCoder } = require("ethers/lib/utils");

const generateMerkleProof = (address, addresses) => {
  const tree = StandardMerkleTree.of(addresses, ["address"]);
  const proof = tree.getProof([address]);

  return proof;
};

const main = async () => {
  const address = process.argv[2];

  const addresses = JSON.parse(
    fs.readFileSync(path.join(__dirname, "./whitelist.json"), {
      encoding: "utf8",
    })
  ).map((address) => [address]);

  const proof = generateMerkleProof(address, addresses);
  process.stdout.write(defaultAbiCoder.encode(["bytes32[]"], [proof]));
  process.exit();
};

main();

module.exports = { generateMerkleProof };
