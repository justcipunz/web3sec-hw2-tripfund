pragma solidity 0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TripFundV2} from "../src/TripFundV2.sol";

contract Upgrade is Script {
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function run() external returns (TripFundV2 implementationV2, ProxyAdmin proxyAdmin) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        address adminAddress = address(uint160(uint256(vm.load(proxyAddress, ADMIN_SLOT))));
        proxyAdmin = ProxyAdmin(adminAddress);

        vm.startBroadcast(privateKey);
        implementationV2 = new TripFundV2();
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(proxyAddress), address(implementationV2), bytes(""));
        vm.stopBroadcast();

        console2.log("ImplementationV2", address(implementationV2));
        console2.log("Proxy", proxyAddress);
        console2.log("ProxyAdmin", address(proxyAdmin));
    }
}
