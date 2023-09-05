// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/foundry-tests/utils/Deployers.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {MockERC20} from "@uniswap/v4-core/test/foundry-tests/utils/MockERC20.sol";
import {PoolModifyPositionTest} from "@uniswap/v4-core/contracts/test/PoolModifyPositionTest.sol";
import {PoolManager} from "@uniswap/v4-core/contracts/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {V4Router} from "../contracts/V4Router.sol";
import {IV4Router} from "../contracts/interfaces/IV4Router.sol";
import {V4RouterImplementation} from "./shared/implementation/V4RouterImplementation.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";

contract V4RouterTest is Test, Deployers, GasSnapshot {
    using CurrencyLibrary for Currency;

    PoolManager manager;
    PoolModifyPositionTest positionManager;
    V4RouterImplementation router;

    MockERC20 token0;
    MockERC20 token1;
    MockERC20 token2;
    MockERC20 token3;

    PoolKey key0;
    PoolKey key1;
    PoolKey key2;

    MockERC20[] tokenPath;

    function setUp() public {
        manager = new PoolManager(500000);
        router = new V4RouterImplementation(manager);
        positionManager = new PoolModifyPositionTest(manager);

        token0 = new MockERC20("Test0", "0", 18, 2 ** 128);
        token1 = new MockERC20("Test1", "1", 18, 2 ** 128);
        token2 = new MockERC20("Test2", "2", 18, 2 ** 128);
        token3 = new MockERC20("Test3", "3", 18, 2 ** 128);

        key0 = createPoolKey(token0, token1);
        key1 = createPoolKey(token1, token2);
        key2 = createPoolKey(token2, token3);

        setupPool(key0);
        setupPool(key1);
        setupPool(key2);

        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        token2.approve(address(router), type(uint256).max);
        token3.approve(address(router), type(uint256).max);
    }

    function testRouter_bytecodeSize() public {
        snapSize("RouterBytecode", address(router));
    }

    function testRouter_swapExactInputSingle_zeroForOne() public {
        uint256 amountIn = 1 ether;
        uint256 expectedAmountOut = 992054607780215625;

        IV4Router.ExactInputSingleParams memory params =
            IV4Router.ExactInputSingleParams(key0, true, address(this), uint128(amountIn), 0, 0);

        uint256 prevBalance0 = token0.balanceOf(address(this));
        uint256 prevBalance1 = token1.balanceOf(address(this));

        snapStart("RouterExactInputSingle");
        router.swap(IV4Router.SwapType.ExactInputSingle, abi.encode(params));
        snapEnd();

        uint256 newBalance0 = token0.balanceOf(address(this));
        uint256 newBalance1 = token1.balanceOf(address(this));

        assertEq(prevBalance0 - newBalance0, amountIn);
        assertEq(newBalance1 - prevBalance1, expectedAmountOut);
    }

    function testRouter_swapExactInputSingle_oneForZero() public {
        uint256 amountIn = 1 ether;
        uint256 expectedAmountOut = 992054607780215625;

        IV4Router.ExactInputSingleParams memory params =
            IV4Router.ExactInputSingleParams(key0, false, address(this), uint128(amountIn), 0, 0);

        uint256 prevBalance0 = token0.balanceOf(address(this));
        uint256 prevBalance1 = token1.balanceOf(address(this));

        router.swap(IV4Router.SwapType.ExactInputSingle, abi.encode(params));

        uint256 newBalance0 = token0.balanceOf(address(this));
        uint256 newBalance1 = token1.balanceOf(address(this));

        assertEq(prevBalance1 - newBalance1, amountIn);
        assertEq(newBalance0 - prevBalance0, expectedAmountOut);
    }

    function testRouter_swapExactIn_1Hop_zeroForOne() public {
        uint256 amountIn = 1 ether;
        uint256 expectedAmountOut = 992054607780215625;

        tokenPath.push(token0);
        tokenPath.push(token1);
        IV4Router.ExactInputParams memory params = getExactInputParams(tokenPath, amountIn);

        uint256 prevBalance0 = token0.balanceOf(address(this));
        uint256 prevBalance1 = token1.balanceOf(address(this));

        snapStart("RouterExactIn1Hop");
        router.swap(IV4Router.SwapType.ExactInput, abi.encode(params));
        snapEnd();

        uint256 newBalance0 = token0.balanceOf(address(this));
        uint256 newBalance1 = token1.balanceOf(address(this));

        assertEq(prevBalance0 - newBalance0, amountIn);
        assertEq(newBalance1 - prevBalance1, expectedAmountOut);
    }

    function testRouter_swapExactIn_1Hop_oneForZero() public {
        uint256 amountIn = 1 ether;
        uint256 expectedAmountOut = 992054607780215625;

        tokenPath.push(token1);
        tokenPath.push(token0);
        IV4Router.ExactInputParams memory params = getExactInputParams(tokenPath, amountIn);
        uint256 prevBalance0 = token0.balanceOf(address(this));
        uint256 prevBalance1 = token1.balanceOf(address(this));

        router.swap(IV4Router.SwapType.ExactInput, abi.encode(params));

        uint256 newBalance0 = token0.balanceOf(address(this));
        uint256 newBalance1 = token1.balanceOf(address(this));

        assertEq(prevBalance1 - newBalance1, amountIn);
        assertEq(newBalance0 - prevBalance0, expectedAmountOut);
    }

    function testRouter_swapExactIn_2Hops() public {
        uint256 amountIn = 1 ether;
        uint256 expectedAmountOut = 984211133872795298;

        tokenPath.push(token0);
        tokenPath.push(token1);
        tokenPath.push(token2);
        IV4Router.ExactInputParams memory params = getExactInputParams(tokenPath, amountIn);

        uint256 prevBalance0 = token0.balanceOf(address(this));
        uint256 prevBalance1 = token1.balanceOf(address(this));
        uint256 prevBalance2 = token2.balanceOf(address(this));

        snapStart("RouterExactIn2Hops");
        router.swap(IV4Router.SwapType.ExactInput, abi.encode(params));
        snapEnd();

        uint256 newBalance0 = token0.balanceOf(address(this));
        uint256 newBalance1 = token1.balanceOf(address(this));
        uint256 newBalance2 = token2.balanceOf(address(this));

        assertEq(prevBalance0 - newBalance0, amountIn);
        assertEq(prevBalance1 - newBalance1, 0);
        assertEq(newBalance2 - prevBalance2, expectedAmountOut);
        assertEq(token0.balanceOf(address(router)), 0);
        assertEq(token1.balanceOf(address(router)), 0);
        assertEq(token2.balanceOf(address(router)), 0);
    }

    function testRouter_swapExactIn_3Hops() public {
        uint256 amountIn = 1 ether;
        uint256 expectedAmountOut = 976467664490096191;

        tokenPath.push(token0);
        tokenPath.push(token1);
        tokenPath.push(token2);
        tokenPath.push(token3);
        IV4Router.ExactInputParams memory params = getExactInputParams(tokenPath, amountIn);

        uint256 prevBalance0 = token0.balanceOf(address(this));
        uint256 prevBalance3 = token3.balanceOf(address(this));

        snapStart("RouterExactIn3Hops");
        router.swap(IV4Router.SwapType.ExactInput, abi.encode(params));
        snapEnd();

        uint256 newBalance0 = token0.balanceOf(address(this));
        uint256 newBalance3 = token3.balanceOf(address(this));

        assertEq(prevBalance0 - newBalance0, amountIn);
        assertEq(newBalance3 - prevBalance3, expectedAmountOut);
        assertEq(token0.balanceOf(address(router)), 0);
        assertEq(token1.balanceOf(address(router)), 0);
        assertEq(token2.balanceOf(address(router)), 0);
        assertEq(token3.balanceOf(address(router)), 0);
    }

    function testRouter_swapExactOutputSingle_zeroForOne() public {
        uint256 amountOut = 1 ether;
        uint256 expectedAmountIn = 1008049273448486163;

        IV4Router.ExactOutputSingleParams memory params =
            IV4Router.ExactOutputSingleParams(key0, true, address(this), uint128(amountOut), 0, 0);

        uint256 prevBalance0 = token0.balanceOf(address(this));
        uint256 prevBalance1 = token1.balanceOf(address(this));

        snapStart("RouterExactOutputSingle");
        router.swap(IV4Router.SwapType.ExactOutputSingle, abi.encode(params));
        snapEnd();

        uint256 newBalance0 = token0.balanceOf(address(this));
        uint256 newBalance1 = token1.balanceOf(address(this));

        assertEq(prevBalance0 - newBalance0, expectedAmountIn);
        assertEq(newBalance1 - prevBalance1, amountOut);
    }

    function testRouter_swapExactOutputSingle_oneForZero() public {
        uint256 amountOut = 1 ether;
        uint256 expectedAmountIn = 1008049273448486163;

        IV4Router.ExactOutputSingleParams memory params =
            IV4Router.ExactOutputSingleParams(key0, false, address(this), uint128(amountOut), 0, 0);

        uint256 prevBalance0 = token0.balanceOf(address(this));
        uint256 prevBalance1 = token1.balanceOf(address(this));

        router.swap(IV4Router.SwapType.ExactOutputSingle, abi.encode(params));

        uint256 newBalance0 = token0.balanceOf(address(this));
        uint256 newBalance1 = token1.balanceOf(address(this));

        assertEq(prevBalance1 - newBalance1, expectedAmountIn);
        assertEq(newBalance0 - prevBalance0, amountOut);
    }

    function testRouter_swapExactOut_1Hop_zeroForOne() public {
        uint256 amountOut = 1 ether;
        uint256 expectedAmountIn = 1008049273448486163;

        tokenPath.push(token0);
        tokenPath.push(token1);
        IV4Router.ExactOutputParams memory params = getExactOutputParams(tokenPath, amountOut);

        uint256 prevBalance0 = token0.balanceOf(address(this));
        uint256 prevBalance1 = token1.balanceOf(address(this));

        snapStart("RouterExactOut1Hop");
        router.swap(IV4Router.SwapType.ExactOutput, abi.encode(params));
        snapEnd();

        uint256 newBalance0 = token0.balanceOf(address(this));
        uint256 newBalance1 = token1.balanceOf(address(this));

        assertEq(prevBalance0 - newBalance0, expectedAmountIn);
        assertEq(newBalance1 - prevBalance1, amountOut);
    }

    function testRouter_swapExactOut_1Hop_oneForZero() public {
        uint256 amountOut = 1 ether;
        uint256 expectedAmountIn = 1008049273448486163;

        tokenPath.push(token1);
        tokenPath.push(token0);
        IV4Router.ExactOutputParams memory params = getExactOutputParams(tokenPath, amountOut);

        uint256 prevBalance0 = token0.balanceOf(address(this));
        uint256 prevBalance1 = token1.balanceOf(address(this));

        snapStart("RouterExactOut1Hop");
        router.swap(IV4Router.SwapType.ExactOutput, abi.encode(params));
        snapEnd();

        uint256 newBalance0 = token0.balanceOf(address(this));
        uint256 newBalance1 = token1.balanceOf(address(this));

        assertEq(prevBalance1 - newBalance1, expectedAmountIn);
        assertEq(newBalance0 - prevBalance0, amountOut);
    }

    function testRouter_swapExactOut_2Hops() public {
        uint256 amountOut = 1 ether;
        uint256 expectedAmountIn = 1016204441757464409;

        tokenPath.push(token0);
        tokenPath.push(token1);
        tokenPath.push(token2);
        IV4Router.ExactOutputParams memory params = getExactOutputParams(tokenPath, amountOut);

        uint256 prevBalance0 = token0.balanceOf(address(this));
        uint256 prevBalance1 = token1.balanceOf(address(this));
        uint256 prevBalance2 = token2.balanceOf(address(this));

        snapStart("RouterExactOut2Hops");
        router.swap(IV4Router.SwapType.ExactOutput, abi.encode(params));
        snapEnd();

        uint256 newBalance0 = token0.balanceOf(address(this));
        uint256 newBalance1 = token1.balanceOf(address(this));
        uint256 newBalance2 = token2.balanceOf(address(this));

        assertEq(prevBalance0 - newBalance0, expectedAmountIn);
        assertEq(prevBalance1 - newBalance1, 0);
        assertEq(newBalance2 - prevBalance2, amountOut);
        assertEq(token0.balanceOf(address(router)), 0);
        assertEq(token1.balanceOf(address(router)), 0);
        assertEq(token2.balanceOf(address(router)), 0);
    }

    function testRouter_swapExactOut_3Hops() public {
        uint256 amountOut = 1 ether;
        uint256 expectedAmountIn = 1024467570922834110;

        tokenPath.push(token0);
        tokenPath.push(token1);
        tokenPath.push(token2);
        tokenPath.push(token3);
        IV4Router.ExactOutputParams memory params = getExactOutputParams(tokenPath, amountOut);

        uint256 prevBalance0 = token0.balanceOf(address(this));
        uint256 prevBalance3 = token3.balanceOf(address(this));

        snapStart("RouterExactOut3Hops");
        router.swap(IV4Router.SwapType.ExactOutput, abi.encode(params));
        snapEnd();

        uint256 newBalance0 = token0.balanceOf(address(this));
        uint256 newBalance3 = token3.balanceOf(address(this));

        assertEq(prevBalance0 - newBalance0, expectedAmountIn);
        assertEq(newBalance3 - prevBalance3, amountOut);
        assertEq(token0.balanceOf(address(router)), 0);
        assertEq(token1.balanceOf(address(router)), 0);
        assertEq(token2.balanceOf(address(router)), 0);
        assertEq(token3.balanceOf(address(router)), 0);
    }

    function createPoolKey(MockERC20 tokenA, MockERC20 tokenB) internal pure returns (PoolKey memory) {
        if (address(tokenA) > address(tokenB)) (tokenA, tokenB) = (tokenB, tokenA);
        return PoolKey(Currency.wrap(address(tokenA)), Currency.wrap(address(tokenB)), 3000, 60, IHooks(address(0)));
    }

    function setupPool(PoolKey memory poolKey) internal {
        manager.initialize(poolKey, SQRT_RATIO_1_1, ZERO_BYTES);
        MockERC20(Currency.unwrap(poolKey.currency0)).approve(address(positionManager), type(uint256).max);
        MockERC20(Currency.unwrap(poolKey.currency1)).approve(address(positionManager), type(uint256).max);
        positionManager.modifyPosition(poolKey, IPoolManager.ModifyPositionParams(-887220, 887220, 200 ether));
    }

    function toCurrency(MockERC20 token) internal pure returns (Currency) {
        return Currency.wrap(address(token));
    }

    function getExactInputParams(MockERC20[] memory _tokenPath, uint256 amountIn)
        internal
        view
        returns (IV4Router.ExactInputParams memory params)
    {
        IV4Router.PathKey[] memory path = new IV4Router.PathKey[](_tokenPath.length - 1);
        for (uint256 i = 0; i < _tokenPath.length - 1; i++) {
            path[i] = IV4Router.PathKey(Currency.wrap(address(_tokenPath[i + 1])), 3000, 60, IHooks(address(0)));
        }

        params.currencyIn = Currency.wrap(address(_tokenPath[0]));
        params.path = path;
        params.recipient = address(this);
        params.amountIn = uint128(amountIn);
        params.amountOutMinimum = 0;
    }

    function getExactOutputParams(MockERC20[] memory _tokenPath, uint256 amountOut)
        internal
        view
        returns (IV4Router.ExactOutputParams memory params)
    {
        IV4Router.PathKey[] memory path = new IV4Router.PathKey[](_tokenPath.length - 1);
        for (uint256 i = _tokenPath.length - 1; i > 0; i--) {
            path[i - 1] = IV4Router.PathKey(Currency.wrap(address(_tokenPath[i - 1])), 3000, 60, IHooks(address(0)));
        }

        params.currencyOut = Currency.wrap(address(_tokenPath[_tokenPath.length - 1]));
        params.path = path;
        params.recipient = address(this);
        params.amountOut = uint128(amountOut);
        params.amountInMaximum = type(uint128).max;
    }
}