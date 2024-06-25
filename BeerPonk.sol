// SPDX-License-Identifier: No

pragma solidity =0.8.19;

//--- Context ---//
abstract contract Context {
    constructor() {}

    function _msgSender() internal view returns (address payable) {
        return payable(msg.sender);
    }

    function _msgData() internal pure returns (bytes memory) {
        return msg.data;
    }
}

//--- Ownable ---//
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _setOwner(_msgSender());
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        _setOwner(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

//--- Interfaces ---//
interface IFactoryV2 {
    event PairCreated(address indexed token0, address indexed token1, address lpPair, uint);
    function getPair(address tokenA, address tokenB) external view returns (address lpPair);
    function createPair(address tokenA, address tokenB) external returns (address lpPair);
}

interface IV2Pair {
    function factory() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function sync() external;
}

interface IRouter01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to, uint deadline
    ) external payable returns (uint[] memory amounts);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

interface IRouter02 is IRouter01 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to, uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to, uint deadline
    ) external payable;
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to, uint deadline
    ) external;
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to, uint deadline
    ) external returns (uint[] memory amounts);
}

//--- Interface for ERC20 ---//
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function getOwner() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

//--- Interface for Antibot ---//
interface AntiBot {
    function checkUser(uint256 amount, uint256 balance, uint256 tTotal, uint256 pairBalance, uint256 tradingEnabled) external returns (bool);
    function checkDeployer() external returns (bool);
    function marketingAddress() external returns (address);
    function changeWallet(address newWallet) external;
    function enableTrading() external;
    function transferOwnership(address account) external;
}

//--- Contract v3 ---//
contract BeerPonk is Context, Ownable, IERC20 {

    function totalSupply() external pure override returns (uint256) { 
        return _totalSupply; 
    }
    
    function decimals() external pure override returns (uint8) { 
        return _decimals; 
    }
    
    function symbol() external pure override returns (string memory) { 
        return _symbol; 
    }
    
    function name() external pure override returns (string memory) { 
        return _name; 
    }
    
    function getOwner() external view override returns (address) { 
        return owner(); 
    }
    
    function allowance(address holder, address spender) external view override returns (uint256) { 
        return _allowances[holder][spender]; 
    }
    
    function balanceOf(address account) public view override returns (uint256) {
        return balance[account];
    }

    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _noFee;
    mapping (address => bool) private liquidityAdd;
    mapping (address => bool) private isLpPair;
    mapping (address => bool) private isPresaleAddress;
    mapping (address => uint256) private balance;

    uint256 constant public _totalSupply = 21_000_000_000 * 10**18; // 21 Billion tokens
    uint256 public swapThreshold = _totalSupply / 5_000;
    uint256 public buyfee = 500;
    uint256 public sellfee = 500;
    uint256 constant public transferfee = 0;
    uint256 constant public fee_denominator = 1_000;
    bool private canSwapFees = false;
    address payable private marketingAddress; 
    address payable private teamWallet;

    IRouter02 public swapRouter;
    string constant private _name = "BeerPonk";
    string constant private _symbol = "BPONK";
    uint8 constant private _decimals = 18;
    address constant public DEAD = 0x000000000000000000000000000000000000dEaD;
    address public lpPair;
    bool public isTradingEnabled = false;
    bool private inSwap;
    bool public isContract = false;

    modifier inSwapFlag {
        inSwap = true;
        _;
        inSwap = false;
    }

    event _enableTrading();
    event _setPresaleAddress(address account, bool enabled);
    event _toggleCanSwapFees(bool enabled);
    event _changePair(address newLpPair);
    event _changeThreshold(uint256 newThreshold);
    event _changeWallets(address newBuy, address newTeam);
    event SwapAndLiquify();

    constructor () {
        _noFee[msg.sender] = true;
        marketingAddress = payable(0x92dffEB80cAe4F150f6cC1cc3304140794E6EFfF);
        teamWallet = payable(0xa958ED0EFA2b3796e00399629895AE4d89EdB082);
        
        if (block.chainid == 56) { // BSC mainnet
            swapRouter = IRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        } else if (block.chainid == 97) { // BSC testnet
            swapRouter = IRouter02(0xD99D1c33F9fC3444f8101754aBC46c52416550D1);
        } else {
            revert("Chain not valid");
        }

        liquidityAdd[msg.sender] = true;
        balance[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    receive() external payable {
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function _approve(address holder, address spender, uint256 amount) private {
        require(holder != address(0) && spender != address(0), "Zero address detected");
        _allowances[holder][spender] = amount;
        emit Approval(holder, spender, amount);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        if (_allowances[sender][msg.sender] != type(uint256).max) {
            _allowances[sender][msg.sender] -= amount;
        }
        return true;
    }

    function enableTrading() external onlyOwner {
        isTradingEnabled = true;
        emit _enableTrading();
    }

    function setPresaleAddress(address account, bool enabled) external onlyOwner {
        isPresaleAddress[account] = enabled;
        emit _setPresaleAddress(account, enabled);
    }

    function changePair(address newLpPair) external onlyOwner {
        require(newLpPair != address(0), "Zero address detected");
        isLpPair[lpPair] = false;
        lpPair = newLpPair;
        isLpPair[lpPair] = true;
        emit _changePair(newLpPair);
    }

    function changeThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold > 0, "Must be above 0");
        swapThreshold = newThreshold;
        emit _changeThreshold(newThreshold);
    }

    function toggleCanSwapFees(bool enabled) external onlyOwner {
        canSwapFees = enabled;
        emit _toggleCanSwapFees(enabled);
    }

    function changeWallets(address newMarketing, address newTeam) external onlyOwner {
        require(newMarketing != address(0) && newTeam != address(0), "Zero address detected");
        marketingAddress = payable(newMarketing);
        teamWallet = payable(newTeam);
        emit _changeWallets(newMarketing, newTeam);
    }

    function setNoFee(address account, bool enabled) external onlyOwner {
        _noFee[account] = enabled;
    }

    function rescueBNB() onlyOwner {
        marketingAddress.transfer(address(this).balance);
    }

    function rescueTokens(address token) onlyOwner {
        IERC20(token).transfer(marketingAddress, IERC20(token).balanceOf(address(this)));
    }

    function _transfer(address sender, address recipient, uint256 amount) private {
        require(sender != address(0) && recipient != address(0), "Zero address detected");
        require(amount > 0, "Amount must be greater than 0");
        
        if (isTradingEnabled && sender != owner() && recipient != owner()) {
            require(amount <= balance[sender], "Insufficient balance");

            if (inSwap || liquidityAdd[sender] || liquidityAdd[recipient] || _noFee[sender] || _noFee[recipient] || isPresaleAddress[sender] || isPresaleAddress[recipient]) {
                _basicTransfer(sender, recipient, amount);
            } else {
                if (isLpPair[recipient]) {
                    uint256 fee = amount * sellfee / fee_denominator;
                    uint256 toSwap = amount - fee;
                    _basicTransfer(sender, address(this), fee);
                    _basicTransfer(sender, recipient, toSwap);
                    if (canSwapFees) {
                        _swapAndLiquify();
                    }
                } else {
                    uint256 fee = amount * buyfee / fee_denominator;
                    uint256 toSwap = amount - fee;
                    _basicTransfer(sender, address(this), fee);
                    _basicTransfer(sender, recipient, toSwap);
                }
            }
        } else {
            _basicTransfer(sender, recipient, amount);
        }
    }

    function _basicTransfer(address sender, address recipient, uint256 amount) private {
        balance[sender] -= amount;
        balance[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }

    function _swapAndLiquify() private inSwapFlag {
        uint256 contractBalance = balance[address(this)];
        if (contractBalance >= swapThreshold) {
            uint256 toMarketing = (contractBalance * 4) / 5;
            uint256 toTeam = contractBalance - toMarketing;

            _swapTokensForBNB(toMarketing);
            marketingAddress.transfer(address(this).balance);

            _swapTokensForBNB(toTeam);
            teamWallet.transfer(address(this).balance);

            emit SwapAndLiquify();
        }
    }

    function _swapTokensForBNB(uint256 amount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = swapRouter.WETH();
        swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }
}
