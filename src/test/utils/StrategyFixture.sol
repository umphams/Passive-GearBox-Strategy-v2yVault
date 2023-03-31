// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ExtendedTest} from "./ExtendedTest.sol";
import {Vm} from "forge-std/Vm.sol";
import {IVault} from "../../interfaces/Vault.sol";
import {Strategy} from "../../Strategy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

string constant vaultArtifact = "artifacts/Vault.json";

contract StrategyFixture is ExtendedTest {
    using SafeERC20 for IERC20;

    struct AssetFixture {
        IVault vault;
        Strategy strategy;
        IERC20 want;
    }

    IERC20 public weth;

    AssetFixture[] public assetFixtures;

    mapping(string => address) public tokenAddrs;
    mapping(string => uint256) public tokenPrices;
    mapping(string => address) public poolService;

    address public gov = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;
    address public user = address(1);
    address public whale = address(2);
    address public rewards = address(3);
    address public guardian = address(4);
    address public management = address(5);
    address public strategist = address(6);
    address public keeper = address(7);

    uint256 public minFuzzAmt = 1_000 ether;
    // @dev maximum amount of want tokens deposited based on @maxDollarNotional
    uint256 public maxFuzzAmt = 1_000_000 ether; // keeping in mind the WETH mod --> 100 WETH --> 0.1 WETH
    // @dev maximum dollar amount of tokens to be deposited
    uint256 public constant DELTA = 10 ** 1;

    function setUp() public virtual {
        _setTokenPrices();
        _setTokenAddrs();
        _setPoolService();

        weth = IERC20(tokenAddrs["WETH"]);
        
        // string[1] memory _tokensToTest = ["WETH"]; // for single test
        string[4] memory _tokensToTest = ["DAI", "USDC", "WETH", "FRAX"];

        for (uint8 i = 0; i < _tokensToTest.length; ++i) {
            string memory _tokenToTest = _tokensToTest[i];
            IERC20 _want = IERC20(tokenAddrs[_tokenToTest]);
            
            (address _vault, address _strategy) = deployVaultAndStrategy(
                address(_want),
                _tokenToTest,
                gov,
                rewards,
                IERC20Metadata(address(_want)).name(),
                IERC20Metadata(address(_want)).symbol(),
                guardian,
                management,
                keeper,
                strategist
            );

            assetFixtures.push(AssetFixture(IVault(_vault), Strategy(_strategy), _want));

            vm.label(address(_vault), string(abi.encodePacked(_tokenToTest, "Vault")));
            vm.label(address(_strategy), string(abi.encodePacked(_tokenToTest, "Strategy")));
            vm.label(address(_want), _tokenToTest);
        }

        // add more labels to make your traces readable
        vm.label(gov, "Gov");
        vm.label(user, "User");
        vm.label(whale, "Whale");
        vm.label(rewards, "Rewards");
        vm.label(guardian, "Guardian");
        vm.label(management, "Management");
        vm.label(strategist, "Strategist");
        vm.label(keeper, "Keeper");
    }        

    // Deploys a vault
    function deployVault(
        address _token,
        address _gov,
        address _rewards,
        string memory _name,
        string memory _symbol,
        address _guardian,
        address _management
    ) public returns (address) {
        vm.prank(_gov);
        address _vaultAddress = deployCode(vaultArtifact);
        IVault _vault = IVault(_vaultAddress);

        vm.prank(_gov);
        _vault.initialize(_token, _gov, _rewards, _name, _symbol, _guardian, _management);

        vm.prank(_gov);
        _vault.setDepositLimit(type(uint256).max);

        return address(_vault);
    }

    // Deploys a strategy
    function deployStrategy(address _vault, string memory _tokenSymbol) public returns (address) {
        Strategy _strategy = new Strategy(
            _vault,
            poolService[_tokenSymbol]
        );
        return address(_strategy);
    }

    // Deploys a vault and strategy attached to vault
    function deployVaultAndStrategy(
        address _token,
        string memory _tokenSymbol,
        address _gov,
        address _rewards,
        string memory _name,
        string memory _symbol,
        address _guardian,
        address _management,
        address _keeper,
        address _strategist
    ) public returns (address _vaultAddr, address _strategyAddr) {
        _vaultAddr = deployVault(_token, _gov, _rewards, _name, _symbol, _guardian, _management);
        IVault _vault = IVault(_vaultAddr);

        vm.prank(_strategist);
        _strategyAddr = deployStrategy(_vaultAddr, _tokenSymbol);
        Strategy _strategy = Strategy(_strategyAddr);

        vm.prank(_strategist);
        _strategy.setKeeper(_keeper);

        vm.prank(_gov);
        _vault.addStrategy(_strategyAddr, 10_000, 0, type(uint256).max, 1_000);

        return (address(_vault), address(_strategy));
    }

    function _setTokenAddrs() internal {
        tokenAddrs["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddrs["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddrs["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokenAddrs["FRAX"] = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    }

    function _setTokenPrices() internal {
        tokenPrices["DAI"] = 1;
        tokenPrices["USDC"] = 1;
        tokenPrices["WETH"] = 2_000;
        tokenPrices["WBTC"] = 30_000;
        tokenPrices["FRAX"] = 1;
    }

    function _setPoolService() internal {
        poolService["DAI"] = 0x24946bCbBd028D5ABb62ad9B635EB1b1a67AF668;
        poolService["USDC"] = 0x86130bDD69143D8a4E5fc50bf4323D48049E98E4;
        poolService["WETH"] = 0xB03670c20F87f2169A7c4eBE35746007e9575901;
        poolService["WBTC"] = 0xB2A015c71c17bCAC6af36645DEad8c572bA08A08;
        poolService["FRAX"] = 0x79012c8d491DcF3A30Db20d1f449b14CAF01da6C;
    }

}
