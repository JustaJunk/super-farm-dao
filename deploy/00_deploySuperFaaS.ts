import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { BigNumber } from "@ethersproject/bignumber";

const NAME = "SuperFaaSToken";
const SYMBOL = "SFST";
const HOST = "0xF0d7d1D47109bA426B9D8A3Cde1941327af1eea3";
const CFA_V1 = "0xECa8056809e7e8db04A8fF6e4E82cD889a46FE2F";
const fDAIx = "0xe3cb950cb164a31c66e32c320a800d477019dcff";
const ETH_ORACLE = "0x9326BFA02ADD2366b30bacB125260Af641031331";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy, read } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();
  const chainId = await hre.getChainId();
  if (chainId !== "42" && chainId !== "1337") {
      console.error("Kovan testnet only");
      return;
  } 
  await deploy("SuperFarmDAO", {
    from: deployer,
    args: [
        NAME,
        SYMBOL,
        HOST,
        CFA_V1,
        fDAIx,
        ETH_ORACLE
    ],
    log: true,
  });
};
export default func;
func.tags = ["SuperFarmDAO"];
