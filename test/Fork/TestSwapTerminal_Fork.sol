// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {UniswapV3ForgeQuoter} from "lib/uniswap-v3-foundry-quote/src/UniswapV3ForgeQuoter.sol";

import {PoolTestHelper} from "lib/uniswap-v3-foundry-pool/src/PoolTestHelper.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import "../../src/JBSwapTerminal.sol";
import {IWETH9} from "../../src/interfaces/IWETH9.sol";

import {MetadataResolverHelper} from "lib/juice-contracts-v4/test/helpers/MetadataResolverHelper.sol";
import {JBMultiTerminal} from "lib/juice-contracts-v4/src/JBMultiTerminal.sol"; 

import {JBTokens} from "lib/juice-contracts-v4/src/JBTokens.sol";

import {IJBController} from "lib/juice-contracts-v4/src/interfaces/IJBController.sol";
import {IJBProjects} from "lib/juice-contracts-v4/src/interfaces/IJBProjects.sol";
import {IJBPermissions} from "lib/juice-contracts-v4/src/interfaces/IJBPermissions.sol";
import {IJBDirectory} from "lib/juice-contracts-v4/src/interfaces/IJBDirectory.sol";
import {IJBTerminalStore} from "lib/juice-contracts-v4/src/interfaces/IJBTerminalStore.sol";

import {JBConstants} from "lib/juice-contracts-v4/src/libraries/JBConstants.sol";

import {JBRulesetMetadata} from "lib/juice-contracts-v4/src/structs/JBRulesetMetadata.sol";
import {JBRuleset} from "lib/juice-contracts-v4/src/structs/JBRuleset.sol";

import {JBRulesetConfig} from "lib/juice-contracts-v4/src/structs/JBRulesetConfig.sol";

import {JBSplitGroup} from "lib/juice-contracts-v4/src/structs/JBSplitGroup.sol";

import {JBFundAccessLimitGroup} from "lib/juice-contracts-v4/src/structs/JBFundAccessLimitGroup.sol";

import {IJBRulesetApprovalHook} from "lib/juice-contracts-v4/src/interfaces/IJBRulesetApprovalHook.sol";




import {MockERC20} from "../helper/MockERC20.sol";


import "forge-std/Test.sol";

/// @notice Swap terminal test on a Sepolia fork
contract TestSwapTerminal_Fork is Test {
    IERC20Metadata constant UNI = IERC20Metadata(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
    IWETH9 constant WETH = IWETH9(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14);
    IUniswapV3Pool constant POOL = IUniswapV3Pool(0x287B0e934ed0439E2a7b1d5F0FC25eA2c24b64f7);

    // Other token which is either token0 (if UNI is token1) or token1 of the pool
    IERC20Metadata internal _otherTokenIn = address(UNI) < address(WETH)
        ? IERC20Metadata(address(uint160(address(WETH)) - 1))
        : IERC20Metadata(address(uint160(address(WETH)) + 1));

    IUniswapV3Pool internal _otherTokenPool;

    JBSwapTerminal internal _swapTerminal;
    JBMultiTerminal internal _projectTerminal;
    JBTokens internal _tokens;
    IJBProjects internal _projects;
    IJBPermissions internal _permissions;
    IJBDirectory internal _directory;
    IPermit2 internal _permit2;
    IJBController internal _controller;
    IJBTerminalStore internal _terminalStore;

    address internal _owner;
    address internal _sender;

    uint256 internal _projectId = 4;
    address internal _projectOwner;
    address internal _terminalOwner;
    address internal _beneficiary;

    MetadataResolverHelper internal _metadataResolver;
    UniswapV3ForgeQuoter internal _uniswapV3ForgeQuoter;
    PoolTestHelper internal _poolTestHelper;

    function setUp() public {
        vm.createSelectFork("https://rpc.ankr.com/eth_sepolia", 5_022_528);

        vm.label(address(UNI), "UNI");
        vm.label(address(WETH), "WETH");
        vm.label(address(POOL), "POOL");

        // TODO: find a new way to parse broadcast json
        // _controller = IJBController(stdJson.readAddress(
        //         vm.readFile("broadcast/Deploy.s.sol/11155420/run-latest.json"), ".address"
        //     ));

        _controller = IJBController(0x15e9030Dd25b27d7e6763598B87445daf222C115);
        vm.label(address(_controller), "controller");

        _projects = IJBProjects(0x95df60b57Ee581680F5c243554E16BD4F3A6a192);
        vm.label(address(_projects), "projects");

        _permissions = IJBPermissions(0x607763b1458419Edb09f56CE795057A2958e2001);
        vm.label(address(_permissions), "permissions");

        _directory = IJBDirectory(0x862ea57d0C473a5c7c8330d92C7824dbd60269EC);
        vm.label(address(_directory), "directory");

        _permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
        vm.label(address(_permit2), "permit2");

        _tokens = JBTokens(0xdb42B6D08755c3f09AdB8C35A19A558bc1b40C9b);
        vm.label(address(_tokens), "tokens");

        _terminalStore = IJBTerminalStore(0x6b2c93da6Af4061Eb6dAe4aCFc15632b54c37DE5);
        vm.label(address(_terminalStore), "terminalStore");

        _projectTerminal = JBMultiTerminal(0x4319cb152D46Db72857AfE368B19A4483c0Bff0D);
        vm.label(address(_projectTerminal), "projectTerminal");

        _owner = makeAddr("owner");
        _sender = makeAddr("sender");

        _projectOwner = _projects.ownerOf(_projectId);
        vm.label(_projectOwner, "projectOwner");

        _swapTerminal = new JBSwapTerminal(_projects, _permissions, _directory, _permit2, _owner, WETH);
        vm.label(address(_swapTerminal), "swapTerminal");

        _metadataResolver = new MetadataResolverHelper();
        vm.label(address(_metadataResolver), "metadataResolver");

        _uniswapV3ForgeQuoter = new UniswapV3ForgeQuoter();
        vm.label(address(_uniswapV3ForgeQuoter), "uniswapV3ForgeQuoter");

        _poolTestHelper = new PoolTestHelper();
        vm.label(address(_poolTestHelper), "poolTestHelper");
        
        // Force compiling to make the artifact available for deployCodeTo
        // MockERC20 _ = new MockERC20("MockERC20", "MockERC20", 18);

        deployCodeTo("MockERC20.sol", abi.encode("token", "token", uint8(18)), address(_otherTokenIn));
        vm.label(address(_otherTokenIn), "_otherTokenIn");

        _otherTokenPool = IUniswapV3Pool(
            IUniswapV3Factory(0x0227628f3F023bb0B980b67D528571c95c6DaC1c).createPool(
                address(_otherTokenIn), address(WETH), 3000
            )
        );
        vm.label(address(_otherTokenPool), "_otherTokenPool");

        // Copying UNI sqrt price to hjave a realistic value
        (uint160 _sqrtPrice,,,,,,) = POOL.slot0();
        _otherTokenPool.initialize(_sqrtPrice);

        // Mint some tokens to the pool helper (for an obscure reason, forge std reverts if initial supply is 0)
        MockERC20(address(_otherTokenIn)).mint(address(_poolTestHelper), 1000 * 1e18);
        WETH.deposit{value: 1000 * 1e18}();
        WETH.transfer(address(_poolTestHelper), 1000 * 1e18);

        _poolTestHelper.addLiquidityFullRange(address(_otherTokenPool), 100_000 * 1e18, 100_000 * 1e18);
    }

    /// @notice Test paying a swap terminal in UNI to contribute to JuiceboxDAO project (in the eth terminal), using
    /// metadata
    /// @dev    Quote at the forked block 5022528 : 1 UNI = 1.33649 ETH with max slippage suggested (uni sdk): 0.5%
    function testPayUniSwapEthPayEth() external {
        // NOTE: bullet proofing for coming fuzzed token
        uint256 _amountIn = 10 * 10 ** UNI.decimals();

        deal(address(UNI), address(_sender), _amountIn);

        // 10 uni - 8%
        // uint256 _minAmountOut = 10 * 1.33649 ether * 92 / 100;
        uint256 _minAmountOut = _uniswapV3ForgeQuoter.getAmountOut(POOL, _amountIn, address(UNI));

        vm.prank(_projectOwner);
        _swapTerminal.addDefaultPool(_projectId, address(UNI), POOL);

        // Build the metadata using the minimum amount out, the pool address and the token out address
        bytes[] memory _data = new bytes[](1);
        _data[0] = abi.encode(_minAmountOut, address(POOL), JBConstants.NATIVE_TOKEN);

        // Pass the delegate id
        bytes4[] memory _ids = new bytes4[](1);
        _ids[0] = bytes4("SWAP");

        // Generate the metadata
        bytes memory _metadata = _metadataResolver.createMetadata(_ids, _data);

        // Approve the transfer
        vm.startPrank(_sender);
        UNI.approve(address(_swapTerminal), _amountIn);

        // Make a payment.
        _swapTerminal.pay({
            _projectId: _projectId,
            _amount: _amountIn,
            _token: address(UNI),
            _beneficiary: _beneficiary,
            _minReturnedTokens: 1,
            _memo: "Take my money!",
            _metadata: _metadata
        });

        // // Make sure the beneficiary has a balance of project tokens.
        // uint256 _beneficiaryTokenBalance =
        //     UD60x18unwrap(UD60x18mul(UD60x18wrap(_amountIn * _quote), UD60x18wrap(_weight)));
        // assertEq(_tokens.totalBalanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);

        // // Make sure the native token balance in terminal is up to date.
        // uint256 _terminalBalance = _amountIn * _quote;
        // assertEq(
        //     jbTerminalStore().balanceOf(address(_projectTerminal), _projectId, JBConstants.NATIVE_TOKEN),
        // _terminalBalance
        // );
    }

    /// @notice Test paying a swap terminal in another token, which has an address either bigger or smaller than UNI
    ///         to test the opposite pool token ordering
    function testPayAndSwapOtherTokenOrder() external {
        // NOTE: bullet proofing for coming fuzzed token
        uint256 _amountIn = 10 * 10 ** _otherTokenIn.decimals();

        deal(address(_otherTokenIn), address(_sender), _amountIn);

        uint256 _minAmountOut = _uniswapV3ForgeQuoter.getAmountOut(_otherTokenPool, _amountIn, address(_otherTokenIn));

        vm.prank(_projectOwner);
        _swapTerminal.addDefaultPool(_projectId, address(_otherTokenIn), _otherTokenPool);

        // Build the metadata using the minimum amount out, the pool address and the token out address
        bytes[] memory _data = new bytes[](1);
        _data[0] = abi.encode(_minAmountOut, address(_otherTokenPool), JBConstants.NATIVE_TOKEN);

        // Pass the delegate id
        bytes4[] memory _ids = new bytes4[](1);
        _ids[0] = bytes4("SWAP");

        // Generate the metadata
        bytes memory _metadata = _metadataResolver.createMetadata(_ids, _data);

        // Approve the transfer
        vm.startPrank(_sender);
        _otherTokenIn.approve(address(_swapTerminal), _amountIn);

        // Make a payment.
        _swapTerminal.pay({
            _projectId: _projectId,
            _amount: _amountIn,
            _token: address(_otherTokenIn),
            _beneficiary: _beneficiary,
            _minReturnedTokens: 1,
            _memo: "Take my money!",
            _metadata: _metadata
        });
    }
}
