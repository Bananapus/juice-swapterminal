// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../helper/UnitFixture.sol";

import {JBMetadataResolver} from "@bananapus/core/src/libraries/JBMetadataResolver.sol";
import {IUniswapV3PoolActions} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IPermit2, IAllowanceTransfer} from "@uniswap/permit2/src/interfaces/IPermit2.sol";

contract Pay is UnitFixture {
    address caller;

    address beneficiary;
    address tokenIn;
    address tokenOut;
    IUniswapV3Pool pool;

    address nextTerminal;

    uint256 projectId = 1337;
    function setUp() public override {
        super.setUp();

        caller = makeAddr("caller");
        beneficiary = makeAddr("beneficiary");
        tokenIn = makeAddr("tokenIn");
        tokenOut = makeAddr("tokenOut");
        pool = IUniswapV3Pool(makeAddr("pool"));
        nextTerminal = makeAddr("nextTerminal");
    }

    function test_PayWhenTokenInIsTheNativeToken(uint256 msgValue, uint256 amountIn, uint256 amountOut) public {
        vm.deal(caller, msgValue);

        tokenIn = JBConstants.NATIVE_TOKEN;

        bytes memory quoteMetadata = _createMetadata("SWAP", abi.encode(amountOut, pool, tokenOut));
        
        // Mock the swap - this is where we make most of the tests
        mockExpectCall(
            address(pool),
            abi.encodeCall( 
                IUniswapV3PoolActions.swap,
                (
                    address(swapTerminal),
                    address(mockWETH) < tokenOut,
                    // it should use msg value as amountIn
                    int256(msgValue),
                    address(mockWETH) < tokenOut ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                     // it should use weth as tokenIn
                     // it should set inIsNativeToken to true
                    abi.encode(mockWETH, true)
                )   
            ),
            // 0 for 1 => amount0 is the token in (positive), amount1 is the token out (negative/owed to the pool), and vice versa
            address(mockWETH) < tokenOut ? abi.encode(msgValue, -int256(amountOut)) : abi.encode(-int256(amountOut), msgValue)
        );  

        mockExpectCall(
            address(mockJBDirectory),
            abi.encodeCall(
                IJBDirectory.primaryTerminalOf,
                (projectId, tokenOut)
            ),
            abi.encode(nextTerminal)
        );

        mockExpectSafeApprove(
            tokenOut,
            address(swapTerminal),
            nextTerminal,
            amountOut
        );

        // Mock the call to the next terminal, using the token out as new token in
        mockExpectCall(
            nextTerminal,
            abi.encodeCall(
                IJBTerminal.pay,
                (
                    projectId,
                    tokenOut,
                    amountOut,
                    beneficiary,
                    amountOut,
                    "",
                    quoteMetadata
                )
            ),
            abi.encode(1337)
        );

        // minReturnedTokens is used for the next terminal minAmountOut (where tokenOut is actually becoming the tokenIn,
        // meaning the minReturned insure a min 1:1 token ratio is the next terminal)
        vm.prank(caller);
        swapTerminal.pay{value: msgValue}({
            projectId: projectId,
            token: tokenIn,
            amount: amountIn, // should be discarded
            beneficiary: beneficiary,
            minReturnedTokens: amountOut,
            memo: "",
            metadata: quoteMetadata
        });
    }

    modifier whenTokenInIsAnErc20Token() {
        tokenIn = makeAddr("tokenIn");
        _;
    }

    function test_PayWhenTokenInIsAnErc20Token(uint256 amountIn, uint256 amountOut) public whenTokenInIsAnErc20Token {
        // Should transfer the token in from the caller to the swap terminal
        mockExpectTransferFrom(
            caller,
            address(swapTerminal),
            tokenIn,
            amountIn
        );

        bytes memory quoteMetadata = _createMetadata("SWAP", abi.encode(amountOut, pool, tokenOut));
        
        // Mock the swap - this is where we make most of the tests
        mockExpectCall(
            address(pool),
            abi.encodeCall( 
                IUniswapV3PoolActions.swap,
                (
                    address(swapTerminal),
                    tokenIn < tokenOut,
                    // it should use amountIn as amount in
                    int256(amountIn),
                    tokenIn < tokenOut ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                     // it should use tokenIn
                     // it should set inIsNativeToken to false
                    abi.encode(tokenIn, false)
                )   
            ),
            // 0 for 1 => amount0 is the token in (positive), amount1 is the token out (negative/owed to the pool), and vice versa
            tokenIn < tokenOut ? abi.encode(amountIn, -int256(amountOut)) : abi.encode(-int256(amountOut), amountIn)
        );  

        mockExpectCall(
            address(mockJBDirectory),
            abi.encodeCall(
                IJBDirectory.primaryTerminalOf,
                (projectId, tokenOut)
            ),
            abi.encode(nextTerminal)
        );

        mockExpectSafeApprove(
            tokenOut,
            address(swapTerminal),
            nextTerminal,
            amountOut
        );

        // Mock the call to the next terminal, using the token out as new token in
        mockExpectCall(
            nextTerminal,
            abi.encodeCall(
                IJBTerminal.pay,
                (
                    projectId,
                    tokenOut,
                    amountOut,
                    beneficiary,
                    amountOut,
                    "",
                    quoteMetadata
                )
            ),
            abi.encode(1337)
        );

        // minReturnedTokens is used for the next terminal minAmountOut (where tokenOut is actually becoming the tokenIn,
        // meaning the minReturned insure a min 1:1 token ratio is the next terminal)
        vm.prank(caller);
        swapTerminal.pay{value: 0}({
            projectId: projectId,
            token: tokenIn,
            amount: amountIn, 
            beneficiary: beneficiary,
            minReturnedTokens: amountOut,
            memo: "",
            metadata: quoteMetadata
        });
    }

    function test_PayRevertWhen_AMsgValueIsPassedAlongAnErc20Token(uint256 msgValue, uint256 amountIn, uint256 amountOut) public whenTokenInIsAnErc20Token {
        msgValue = bound(msgValue, 1, type(uint256).max);
        vm.deal(caller, msgValue);
        
        bytes memory quoteMetadata = _createMetadata("SWAP", abi.encode(amountOut, pool, tokenOut));
        
        mockExpectCall(
            address(mockJBDirectory),
            abi.encodeCall(
                IJBDirectory.primaryTerminalOf,
                (projectId, tokenOut)
            ),
            abi.encode(nextTerminal)
        );

        // it should revert
        vm.expectRevert(JBSwapTerminal.NO_MSG_VALUE_ALLOWED.selector);

        vm.prank(caller);
        swapTerminal.pay{value: msgValue}({
            projectId: projectId,
            token: tokenIn,
            amount: amountIn,
            beneficiary: beneficiary,
            minReturnedTokens: amountOut,
            memo: "",
            metadata: quoteMetadata
        });
    }

    function test_PayWhenTokenInUsesAnErc20Approval(uint256 amountIn, uint256 amountOut) public whenTokenInIsAnErc20Token {
        // it should use the token transferFrom
        test_PayWhenTokenInIsAnErc20Token(amountIn, amountOut);
    }

    modifier whenPermit2DataArePassed() {
        
        _;
    }

    function test_PayWhenPermit2DataArePassed(uint256 amountIn, uint256 amountOut) public whenTokenInIsAnErc20Token whenPermit2DataArePassed {
        // 0 amountIn will not trigger a permit2 use
        amountIn = bound(amountIn, 1, type(uint160).max);

        // add the permit2 data to the metadata
        bytes memory payMetadata = _createMetadata("SWAP", abi.encode(amountOut, pool, tokenOut));

        JBSingleAllowanceContext memory context = JBSingleAllowanceContext({
            sigDeadline: 0,
            amount: uint160(amountIn),
            expiration: 0,
            nonce: 0,
            signature: ""
        });

        payMetadata = JBMetadataResolver.addToMetadata(payMetadata, bytes4(uint32(uint160(address(swapTerminal)))), abi.encode(context));
        
        // it should use the permit2 call
        mockExpectCall(
            address(mockPermit2),
            abi.encodeWithSelector(
                bytes4(keccak256("permit(address,((address,uint160,uint48,uint48),address,uint256),bytes)")),
                abi.encode(
                    caller,
                    IAllowanceTransfer.PermitSingle({
                        details: IAllowanceTransfer.PermitDetails({
                            token: tokenIn,
                            amount: uint160(amountIn),
                            expiration: 0,
                            nonce: 0
                        }),
                        spender: address(swapTerminal),
                        sigDeadline: 0
                    }),
                    ""
                )
            ),
            abi.encode("test1")
        );

        vm.mockCall(
            address(mockPermit2),
            abi.encodeWithSelector(
                bytes4(keccak256("transferFrom(address,address,uint160,address)")),
                abi.encode(
                    caller,
                    address(swapTerminal),
                    uint160(amountIn),
                    tokenIn
                )
            ),
            abi.encode("test")
        );

        // no allowance granted outside of permit2
        mockExpectCall(
            tokenIn,
            abi.encodeCall(
                IERC20.allowance,
                (caller, address(swapTerminal))
            ),
            abi.encode(0)
        );

        mockExpectCall(
            tokenIn,
            abi.encodeCall(
                IERC20.balanceOf,
                (
                    address(swapTerminal)
                )
            ),
            abi.encode(amountIn)
        );

        // Mock the swap - this is where we make most of the tests
        mockExpectCall(
            address(pool),
            abi.encodeCall( 
                IUniswapV3PoolActions.swap,
                (
                    address(swapTerminal),
                    tokenIn < tokenOut,
                    // it should use amountIn as amount in
                    int256(amountIn),
                    tokenIn < tokenOut ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                     // it should use tokenIn
                     // it should set inIsNativeToken to false
                    abi.encode(tokenIn, false)
                )   
            ),
            // 0 for 1 => amount0 is the token in (positive), amount1 is the token out (negative/owed to the pool), and vice versa
            tokenIn < tokenOut ? abi.encode(amountIn, -int256(amountOut)) : abi.encode(-int256(amountOut), amountIn)
        );  

        mockExpectCall(
            address(mockJBDirectory),
            abi.encodeCall(
                IJBDirectory.primaryTerminalOf,
                (projectId, tokenOut)
            ),
            abi.encode(nextTerminal)
        );

        mockExpectSafeApprove(
            tokenOut,
            address(swapTerminal),
            nextTerminal,
            amountOut
        );

        // Mock the call to the next terminal, using the token out as new token in
        mockExpectCall(
            nextTerminal,
            abi.encodeCall(
                IJBTerminal.pay,
                (
                    projectId,
                    tokenOut,
                    amountOut,
                    beneficiary,
                    amountOut,
                    "",
                    payMetadata
                )
            ),
            abi.encode(1337)
        );

        // minReturnedTokens is used for the next terminal minAmountOut (where tokenOut is actually becoming the tokenIn,
        // meaning the minReturned insure a min 1:1 token ratio is the next terminal)
        vm.prank(caller);
        swapTerminal.pay{value: 0}({
            projectId: projectId,
            token: tokenIn,
            amount: amountIn, 
            beneficiary: beneficiary,
            minReturnedTokens: amountOut,
            memo: "",
            metadata: payMetadata
        });

    }

    function test_PayRevertWhen_ThePermit2AllowanceIsLessThanTheAmountIn(uint256 amountIn)
        public
        whenTokenInIsAnErc20Token
        whenPermit2DataArePassed
    {
        uint256 amountOut = 1337;

        // 0 amountIn will not trigger a permit2 use
        vm.assume(amountIn > 0);

        // add the permit2 data to the metadata
        bytes memory payMetadata = _createMetadata("SWAP", abi.encode(amountOut, pool, tokenOut));

        JBSingleAllowanceContext memory context = JBSingleAllowanceContext({
            sigDeadline: 0,
            amount: uint160(amountIn) - 1,
            expiration: 0,
            nonce: 0,
            signature: ""
        });

        payMetadata = JBMetadataResolver.addToMetadata(payMetadata, bytes4(uint32(uint160(address(swapTerminal)))), abi.encode(context));

        mockExpectCall(
            address(mockJBDirectory),
            abi.encodeCall(
                IJBDirectory.primaryTerminalOf,
                (projectId, tokenOut)
            ),
            abi.encode(nextTerminal)
        );
        
        // it should revert
        vm.expectRevert(JBSwapTerminal.PERMIT_ALLOWANCE_NOT_ENOUGH.selector);
        vm.prank(caller);
        swapTerminal.pay{value: 0}({
            projectId: projectId,
            token: tokenIn,
            amount: amountIn, 
            beneficiary: beneficiary,
            minReturnedTokens: amountOut,
            memo: "",
            metadata: payMetadata
        });
    }

    modifier whenAQuoteIsProvided() {
        _;
    }

    function test_PayWhenAQuoteIsProvided(uint256 msgValue, uint256 amountIn, uint256 amountOut) public whenAQuoteIsProvided {
        // it should use the quote as amountOutMin
        // it should use the pool passed
        // it should use the token passed as tokenOut
        test_PayWhenTokenInIsTheNativeToken(msgValue, amountIn, amountOut);
    }

    function test_PayRevertWhen_TheAmountReceivedIsLessThanTheAmountOutMin(uint256 msgValue, uint256 minAmountOut, uint256 amountReceived) public whenAQuoteIsProvided {
        minAmountOut = bound(minAmountOut, 1, type(uint256).max);
        amountReceived = bound(amountReceived, 0, minAmountOut - 1);
        vm.deal(caller, msgValue);

        tokenIn = JBConstants.NATIVE_TOKEN;

        bytes memory quoteMetadata = _createMetadata("SWAP", abi.encode(minAmountOut, pool, tokenOut));
        
        // Mock the swap - this is where we make most of the tests
        mockExpectCall(
            address(pool),
            abi.encodeCall( 
                IUniswapV3PoolActions.swap,
                (
                    address(swapTerminal),
                    address(mockWETH) < tokenOut,
                    // it should use msg value as amountIn
                    int256(msgValue),
                    address(mockWETH) < tokenOut ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                     // it should use weth as tokenIn
                     // it should set inIsNativeToken to true
                    abi.encode(mockWETH, true)
                )   
            ),
            // 0 for 1 => amount0 is the token in (positive), amount1 is the token out (negative/owed to the pool), and vice versa
            address(mockWETH) < tokenOut ? abi.encode(msgValue, -int256(amountReceived)) : abi.encode(-int256(amountReceived), msgValue)
        );  

        mockExpectCall(
            address(mockJBDirectory),
            abi.encodeCall(
                IJBDirectory.primaryTerminalOf,
                (projectId, tokenOut)
            ),
            abi.encode(nextTerminal)
        );

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(JBSwapTerminal.MAX_SLIPPAGE.selector, amountReceived, minAmountOut));

        vm.prank(caller);
        swapTerminal.pay{value: msgValue}({
            projectId: projectId,
            token: tokenIn,
            amount: 0, // should be discarded
            beneficiary: beneficiary,
            minReturnedTokens: amountReceived,
            memo: "",
            metadata: quoteMetadata
        });
    }

    function test_PayWhenTheTokenOutIsTheNativeToken() public whenAQuoteIsProvided {
        vm.skip(true);

        // it should use weth as tokenOut
        // it should set outIsNativeToken to true
    }

    modifier whenNoQuoteIsPassed() {
        _;
    }

    function test_PayWhenNoQuoteIsPassed() public whenNoQuoteIsPassed {
        vm.skip(true);

        // it should use the default pool
        // it should take the other pool token as tokenOut
        // it should get a twap and compute a min amount
    }

    function test_PayRevertWhen_NoDefaultPoolIsDefined() public whenNoQuoteIsPassed {
        vm.skip(true);

        // it should revert
    }

    function test_PayRevertWhen_TheAmountReceivedIsLessThanTheTwapAmountOutMin() public whenNoQuoteIsPassed {
        vm.skip(true);

        // it should revert
    }

    function test_PayWhenTheOtherPoolTokenIsTheNativeToken() public {
        vm.skip(true);

        // it should use weth as tokenOut
        // it should set outIsNativeToken to true
        // it should unwrap the tokenOut after swapping
        // it should use the native token for the next terminal pay()
    }

    function test_PayWhenTheTokenOutIsAnErc20Token() public {
        vm.skip(true);

        // it should use tokenOut as tokenOut
        // it should set outIsNativeToken to false
        // it should set the correct approval
        // it should use the tokenOut for the next terminal pay()
    }

    function test_PayRevertWhen_TheTokenOutHasNoTerminalDefined() public {
        vm.skip(true);

        // it should revert
    }
}
