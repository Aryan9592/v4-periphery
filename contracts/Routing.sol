// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {Path} from "./libraries/Path.sol";

/// @title UniswapV4Routing
/// @notice Abstract contract that contains all internal logic needed for routing through Uniswap V4 pools
abstract contract UniswapV4Routing {
    using CurrencyLibrary for Currency;
    using Path for bytes;

    IPoolManager immutable poolManager;

    error NotPoolManager();
    error InvalidSwapType();
    error TooLittleReceived();

    struct SwapInfo {
        SwapType swapType;
        address msgSender;
        bytes params;
    }

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint128 amountIn;
        uint128 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    enum SwapType {
        ExactInput,
        ExactInputSingle,
        ExactOutput,
        ExactOutputSingle
    }

    /// @dev Only the pool manager may call this function
    modifier poolManagerOnly() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    function v4Swap(SwapType swapType, bytes memory params) internal {
        poolManager.lock(abi.encode(SwapInfo(swapType, msg.sender, params)));
    }

    function lockAcquired(bytes calldata encodedSwapInfo) external poolManagerOnly returns (bytes memory) {
        SwapInfo memory swapInfo = abi.decode(encodedSwapInfo, (SwapInfo));

        if (swapInfo.swapType == SwapType.ExactInput) {
            _swapExactInput(abi.decode(swapInfo.params, (ExactInputParams)), swapInfo.msgSender);
        } else {
            revert InvalidSwapType();
        }

        return bytes("");
    }

    function _swapExactInput(ExactInputParams memory params, address msgSender) private {
        bool inputPayed;

        while (true) {
            (PoolKey memory poolKey, bool zeroForOne) = params.path.decodeFirstPoolKeyAndSwapDirection();

            BalanceDelta delta = poolManager.swap(
                poolKey,
                IPoolManager.SwapParams(
                    zeroForOne,
                    int256(int128(params.amountIn)),
                    params.sqrtPriceLimitX96 == 0
                        ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                        : params.sqrtPriceLimitX96
                ),
                bytes("")
            );

            if (!inputPayed) {
                if (zeroForOne) {
                    _pay(
                        Currency.unwrap(poolKey.currency0),
                        msgSender,
                        address(poolManager),
                        uint256(uint128(delta.amount0()))
                    );
                    poolManager.settle(poolKey.currency0);
                } else {
                    _pay(
                        Currency.unwrap(poolKey.currency1),
                        msgSender,
                        address(poolManager),
                        uint256(uint128(delta.amount1()))
                    );
                    poolManager.settle(poolKey.currency1);
                }
                inputPayed = true;
            }

            if (zeroForOne) {
                params.amountIn = uint128(-delta.amount1());
            } else {
                params.amountIn = uint128(-delta.amount0());
            }


            if (params.path.isFinalSwap()) {
                if (zeroForOne) {
                    poolManager.take(poolKey.currency1, msgSender, uint256(uint128(-delta.amount1())));
                } else {
                    poolManager.take(poolKey.currency0, msgSender, uint256(uint128(-delta.amount0())));
                }
                break;
            } else {
                params.path = params.path.skipToken();
            }
        }

        // after final swap, params.amountIn is the amountOut
        if (params.amountIn < params.amountOutMinimum) revert TooLittleReceived();
    }

    function _pay(address token, address payer, address recipient, uint256 amount) internal virtual;
}