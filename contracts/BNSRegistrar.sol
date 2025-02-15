// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./BNS.sol";
import "./IBaseRegistrar.sol";
import "./ReverseRegistrar.sol";
import {PublicResolver} from "./PublicResolver.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./profiles/PreventsZWC.sol";

contract BNSRegistrar is
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    IBaseRegistrar,
    PreventsZWC
{
    // The BNS registry
    BNS public bns;
    // The Reverse Registrar
    ReverseRegistrar public reverseRegistrar;

    // The namehash of the TLD this registrar owns (eg, .b), set upon construction
    bytes32 public baseNode;
    bytes4 private constant INTERFACE_META_ID =
        bytes4(keccak256("supportsInterface(bytes4)"));
    bytes4 private constant ERC721_ID =
        bytes4(
            keccak256("balanceOf(address)") ^
                keccak256("ownerOf(uint256)") ^
                keccak256("approve(address,uint256)") ^
                keccak256("getApproved(uint256)") ^
                keccak256("setApprovalForAll(address,bool)") ^
                keccak256("isApprovedForAll(address,address)") ^
                keccak256("transferFrom(address,address,uint256)") ^
                keccak256("safeTransferFrom(address,address,uint256)") ^
                keccak256("safeTransferFrom(address,address,uint256,bytes)")
        );
    bytes4 private constant RECLAIM_ID =
        bytes4(keccak256("reclaim(uint256,address)"));

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        BNS _bns,
        bytes32 _baseNode,
        ReverseRegistrar _reverseRegistrar
    ) public initializer {
        __ERC721_init("", "");
        __Ownable_init();
        bns = _bns;
        baseNode = _baseNode;
        reverseRegistrar = _reverseRegistrar;
    }

    modifier live() {
        require(bns.owner(baseNode) == address(this));
        _;
    }

    // Set the resolver for the TLD this registrar manages.
    function setResolver(address resolver) external override onlyOwner {
        bns.setResolver(baseNode, resolver);
    }

    /**
     * @dev Register a name.
     * @param name The label to be registered and used for ID (keccak256(name)).
     * @param owner The address that should own the registration.
     * @param data encoded function data used for multicall on public resolver to set records
     * @param resolver The address of the resolver.
     */
    function register(
        string calldata name,
        address owner,
        bytes[] calldata data,
        address resolver
    ) external override {
        _register(name, owner, data, resolver, true, true);
    }

    /**
     * @dev Register a name, without modifying the registry.
     * @param name The label to be registered and used for ID (keccak256(name))
     * @param owner The address that should own the registration.
     * @param data encoded function data used for multicall on public resolver to set records
     * @param resolver The address of the resolver.
     */
    function registerOnly(
        string calldata name,
        address owner,
        bytes[] calldata data,
        address resolver
    ) external {
        _register(name, owner, data, resolver, false, false);
    }

    /**
     * @dev Register a name, .
     * @param name The label to be registered and used for ID (keccak256(name))
     * @param owner The address that should own the registration.
     * @param data encoded function data used for multicall on public resolver to set records
     * @param resolver The address of the resolver.
     * @param updateRegistry if true, will change owner of bytes32(id) node on BNS Registry
     * @param reverseRecord if true, will register a node for msg.sender on Reverse Registry
     */
    function _register(
        string calldata name,
        address owner,
        bytes[] calldata data,
        address resolver,
        bool updateRegistry,
        bool reverseRecord
    ) internal live preventZWC(name) {
        uint256 id = uint256(keccak256(abi.encodePacked(name)));
        _mint(owner, id);
        if (updateRegistry) {
            bns.setSubnodeOwner(baseNode, bytes32(id), owner);
        }
        if (data.length > 0) {
            _setRecords(resolver, keccak256(bytes(name)), data);
        }
        if (reverseRecord) {
            _setReverseRecord(name, resolver, msg.sender);
        }

        emit NameRegistered(id, owner);
    }

    /**
     * @dev Reclaim ownership of a name in BNS, if you own it in the registrar.
     */
    function reclaim(uint256 id, address owner) external override live {
        require(_isApprovedOrOwner(msg.sender, id));
        bns.setSubnodeOwner(baseNode, bytes32(id), owner);
    }

    /**
     * @dev updates record on the Public Resolver for the BNS node of label
     * @param resolverAddress address of the Public resolver
     * @param label label for updating the BNS Registry node
     * @param data encoded function data for setting multiple records
     */
    function _setRecords(
        address resolverAddress,
        bytes32 label,
        bytes[] calldata data
    ) internal {
        bytes32 nodehash = keccak256(abi.encodePacked(baseNode, label));
        PublicResolver resolver = PublicResolver(resolverAddress);
        resolver.multicallWithNodeCheck(nodehash, data);
    }

    /**
     * @dev registers name on Reverse Registrar and updates Public Resolver
     * @param label label to be registered on Reverse Registry and Public Resolver
     * @param resolver address for Public Resolver
     * @param owner address to own the label that is being registered
     */
    function _setReverseRecord(
        string memory label,
        address resolver,
        address owner
    ) internal {
        reverseRegistrar.setNameForAddr(
            msg.sender,
            owner,
            resolver,
            string.concat(label, ".b")
        );
    }

    function supportsInterface(
        bytes4 interfaceID
    )
        public
        pure
        override(ERC721Upgradeable, IERC165Upgradeable)
        returns (bool)
    {
        return
            interfaceID == INTERFACE_META_ID ||
            interfaceID == ERC721_ID ||
            interfaceID == RECLAIM_ID;
    }
}
