const fs = require("fs");
const path = require("path");
const { StandardMerkleTree } = require("@openzeppelin/merkle-tree");

const generateMerkleRoot = () => {
  const addresses = JSON.parse(
    fs.readFileSync(path.join(__dirname, "./whitelist.json"), {
      encoding: "utf8",
    })
  ).map((address) => [address]);

  const tree = StandardMerkleTree.of(addresses, ["address"]);

  return tree.root;
};

const main = async () => {
  const merkleRoot = generateMerkleRoot();

  process.stdout.write(merkleRoot);
  process.exit();
};

main();
