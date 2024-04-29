// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../helper/UnitFixture.sol";

contract JBSwapTerminaladdDefaultPool is UnitFixture {

    address caller;
    address projectOwner;
    address otherProjectOwner;
    address token;
    IUniswapV3Pool pool;

    uint256 projectId = 1337;
    uint256 otherProjectId = 69;

    /// @notice Create random address
    function setUp() public override {
        super.setUp();

        caller = makeAddr("sender");
        projectOwner = makeAddr("projectOwner");
        otherProjectOwner = makeAddr("otherProjectOwner");
        token = makeAddr("token");
        pool = IUniswapV3Pool(makeAddr("pool"));
    }

    modifier givenTheCallerIsAProjectOwner() {
        vm.startPrank(projectOwner);
        _;
    }

    function test_WhenAddingAPoolToItsProject() external givenTheCallerIsAProjectOwner {
        // Set the project owner
        mockExpectCall(address(mockJBProjects), abi.encodeCall(IERC721.ownerOf, (projectId)), abi.encode(projectOwner));

        // decimals() call while setting the accounting context
        mockExpectCall(address(token), abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(18));

        // Add the pool as the project owner
        swapTerminal.addDefaultPool(projectId, token, pool);

        // it should add the pool to the project owned
        (IUniswapV3Pool storedPool, bool zeroForOne) = swapTerminal.getPoolFor(projectId, token);
        assertEq(storedPool, pool);
        assertEq(zeroForOne, address(token) < address(mockWETH));
        
    }

    modifier givenTheCallerIsNotAProjectOwner() {
        // Set the project owner
        mockExpectCall(address(mockJBProjects), abi.encodeCall(IERC721.ownerOf, (projectId)), abi.encode(projectOwner));

        // Add the pool as the project owner
        vm.startPrank(caller);
        _;
    }

    function test_WhenTheCallerHasTheRole() external givenTheCallerIsNotAProjectOwner {
        // Give the permission to the caller
        mockExpectCall(
            address(mockJBPermissions),
            abi.encodeCall(
                IJBPermissions.hasPermission,
                (caller, projectOwner, projectId, JBPermissionIds.ADD_SWAP_TERMINAL_POOL)
            ),
            abi.encode(true)
        );

        // decimals() call while setting the accounting context
        mockExpectCall(address(token), abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(18));

        // Add the pool as permissioned caller
        swapTerminal.addDefaultPool(projectId, token, pool);

        // it should add the pool to the project
        (IUniswapV3Pool storedPool, bool zeroForOne) = swapTerminal.getPoolFor(projectId, token);
        assertEq(storedPool, pool);
        assertEq(zeroForOne, address(token) < address(mockWETH));
    }

    function test_RevertWhen_TheCallerHasNoRole() external givenTheCallerIsNotAProjectOwner {
        // Do not give specific or generic permission to the caller
        mockExpectCall(
            address(mockJBPermissions),
            abi.encodeCall(
                IJBPermissions.hasPermission,
                (caller, projectOwner, projectId, JBPermissionIds.ADD_SWAP_TERMINAL_POOL)
            ),
            abi.encode(false)
        );

        mockExpectCall(
            address(mockJBPermissions),
            abi.encodeCall(
                IJBPermissions.hasPermission,
                (caller, projectOwner, 0, JBPermissionIds.ADD_SWAP_TERMINAL_POOL)
            ),
            abi.encode(false)
        );

        // it should revert
        vm.expectRevert(JBPermissioned.UNAUTHORIZED.selector);
        swapTerminal.addDefaultPool(projectId, token, pool);
    }

    modifier givenTheCallerIsTheTerminalOwner() {
        vm.startPrank(terminalOwner);
        _;
    }

    function test_WhenAddingADefaultPool(uint256 _projectIdWithoutPool) external givenTheCallerIsTheTerminalOwner {
        vm.assume(_projectIdWithoutPool != projectId);

        IUniswapV3Pool otherPool = IUniswapV3Pool(makeAddr("otherPool"));

        // Set a project owner
        mockExpectCall(address(mockJBProjects), abi.encodeCall(IERC721.ownerOf, (projectId)), abi.encode(projectOwner));

        // decimals() call while setting the accounting context
        mockExpectCall(address(token), abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(18));

        // Add the pool for the project wildcard
        swapTerminal.addDefaultPool(0, token, pool);

        // Add the pool for a project
        vm.startPrank(projectOwner);
        swapTerminal.addDefaultPool(projectId, token, otherPool);

        // it should add the pool to any project without a default pool
        (IUniswapV3Pool storedPool, bool zeroForOne) = swapTerminal.getPoolFor(_projectIdWithoutPool, token);
        assertEq(storedPool, pool);
        assertEq(zeroForOne, address(token) < address(mockWETH));

        // it should not override the project pool
        (storedPool, zeroForOne) = swapTerminal.getPoolFor(projectId, token);
        assertEq(storedPool, otherPool);
        assertEq(zeroForOne, address(token) < address(mockWETH));
    }

    function test_RevertWhen_AddingAPoolToAProject() external givenTheCallerIsTheTerminalOwner {
        IUniswapV3Pool otherPool = IUniswapV3Pool(makeAddr("otherPool"));

        // Set a project owner
        mockExpectCall(address(mockJBProjects), abi.encodeCall(IERC721.ownerOf, (projectId)), abi.encode(projectOwner));

        // Do not give specific or generic permission to the caller
        mockExpectCall(
            address(mockJBPermissions),
            abi.encodeCall(
                IJBPermissions.hasPermission,
                (terminalOwner, projectOwner, projectId, JBPermissionIds.ADD_SWAP_TERMINAL_POOL)
            ),
            abi.encode(false)
        );

        mockExpectCall(
            address(mockJBPermissions),
            abi.encodeCall(
                IJBPermissions.hasPermission,
                (terminalOwner, projectOwner, 0, JBPermissionIds.ADD_SWAP_TERMINAL_POOL)
            ),
            abi.encode(false)
        );

        // it should revert
        vm.expectRevert(JBPermissioned.UNAUTHORIZED.selector);
        swapTerminal.addDefaultPool(projectId, token, otherPool);
    }
}