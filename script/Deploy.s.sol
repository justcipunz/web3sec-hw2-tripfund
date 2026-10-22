pragma solidity 0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TripFund} from "../src/TripFund.sol";

contract Deploy is Script {
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function run()
        external
        returns (TripFund implementation, TransparentUpgradeableProxy proxy, ProxyAdmin proxyAdmin)
    {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        IERC20 token = IERC20(vm.envAddress("TOKEN_ADDRESS"));
        address organizer = vm.envAddress("ORGANIZER");
        address proxyOwner = vm.envAddress("PROXY_OWNER");
        uint256 goal = vm.envUint("GOAL");
        uint256 deadline = vm.envUint("DEADLINE");

        vm.startBroadcast(privateKey);
        implementation = new TripFund();
        bytes memory data = abi.encodeCall(TripFund.initialize, (token, organizer, goal, deadline));
        proxy = new TransparentUpgradeableProxy(address(implementation), proxyOwner, data);
        vm.stopBroadcast();

        address adminAddress = address(uint160(uint256(vm.load(address(proxy), ADMIN_SLOT))));
        proxyAdmin = ProxyAdmin(adminAddress);

        console2.log("Implementation", address(implementation));
        console2.log("Proxy", address(proxy));
        console2.log("ProxyAdmin", address(proxyAdmin));
    }
}
