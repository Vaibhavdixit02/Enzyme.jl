module API

import LLVM.API: LLVMValueRef, LLVMModuleRef, LLVMTypeRef, LLVMContextRef
using Enzyme_jll
using Libdl
using LLVM
using CEnum

const EnzymeLogicRef = Ptr{Cvoid}
const EnzymeTypeAnalysisRef = Ptr{Cvoid}
const EnzymeAugmentedReturnPtr = Ptr{Cvoid}
const EnzymeTypeAnalyzerRef = Ptr{Cvoid}
const EnzymeGradientUtilsRef = Ptr{Cvoid}

const UP = Cint(1)
const DOWN = Cint(2)
const BOTH = Cint(3)

struct IntList
    data::Ptr{Int64}
    size::Csize_t
end
IntList() = IntList(Ptr{Int64}(0),0)

@cenum(CConcreteType,
  DT_Anything = 0,
  DT_Integer = 1,
  DT_Pointer = 2,
  DT_Half = 3,
  DT_Float = 4,
  DT_Double = 5,
  DT_Unknown = 6
)

function EnzymeConcreteTypeIsFloat(cc::CConcreteType)
  if cc == DT_Half
    return LLVM.HalfType()
  elseif cc == DT_Float
    return LLVM.FloatType()
  elseif cc == DT_Double
    return LLVM.DoubleType()
  else
    return nothing
  end
end

@cenum(CValueType,
  VT_None = 0,
  VT_Primal = 1,
  VT_Shadow = 2,
  VT_Both = 3
)

function EnzymeBitcodeReplacement(mod, NotToReplace) 
    res = ccall((:EnzymeBitcodeReplacement, libEnzymeBCLoad), UInt8, (LLVM.API.LLVMModuleRef, Ptr{Cstring}, Csize_t), mod, NotToReplace, length(NotToReplace))
    return res 
end

struct EnzymeTypeTree end
const CTypeTreeRef = Ptr{EnzymeTypeTree}

EnzymeNewTypeTree() = ccall((:EnzymeNewTypeTree, libEnzyme), CTypeTreeRef, ())
EnzymeNewTypeTreeCT(T, ctx) = ccall((:EnzymeNewTypeTreeCT, libEnzyme), CTypeTreeRef, (CConcreteType, LLVMContextRef), T, ctx)
EnzymeNewTypeTreeTR(tt) = ccall((:EnzymeNewTypeTreeTR, libEnzyme), CTypeTreeRef, (CTypeTreeRef,), tt)

EnzymeFreeTypeTree(tt) = ccall((:EnzymeFreeTypeTree, libEnzyme), Cvoid, (CTypeTreeRef,), tt)
EnzymeSetTypeTree(dst, src) = ccall((:EnzymeSetTypeTree, libEnzyme), UInt8, (CTypeTreeRef, CTypeTreeRef), dst, src)
EnzymeMergeTypeTree(dst, src) = ccall((:EnzymeMergeTypeTree, libEnzyme), UInt8, (CTypeTreeRef, CTypeTreeRef), dst, src)
function EnzymeCheckedMergeTypeTree(dst, src) 
    legal = Ref{UInt8}(0)
    res = ccall((:EnzymeCheckedMergeTypeTree, libEnzyme), UInt8, (CTypeTreeRef, CTypeTreeRef, Ptr{UInt8}), dst, src, legal)
    return res != 0, legal[] != 0
end
EnzymeTypeTreeOnlyEq(dst, x) = ccall((:EnzymeTypeTreeOnlyEq, libEnzyme), Cvoid, (CTypeTreeRef, Int64), dst, x)
EnzymeTypeTreeLookupEq(dst, x, dl) = ccall((:EnzymeTypeTreeLookupEq, libEnzyme), Cvoid, (CTypeTreeRef, Int64, Cstring), dst, x, dl)
EnzymeTypeTreeCanonicalizeInPlace(dst, x, dl) = ccall((:EnzymeTypeTreeCanonicalizeInPlace, libEnzyme), Cvoid, (CTypeTreeRef, Int64, Cstring), dst, x, dl)
EnzymeTypeTreeData0Eq(dst) = ccall((:EnzymeTypeTreeData0Eq, libEnzyme), Cvoid, (CTypeTreeRef,), dst)
EnzymeTypeTreeInner0(dst) = ccall((:EnzymeTypeTreeInner0, libEnzyme), CConcreteType, (CTypeTreeRef,), dst)
EnzymeTypeTreeShiftIndiciesEq(dst, dl, offset, maxSize, addOffset) =
    ccall((:EnzymeTypeTreeShiftIndiciesEq, libEnzyme), Cvoid, (CTypeTreeRef, Cstring, Int64, Int64, UInt64),
        dst, dl, offset, maxSize, addOffset)

EnzymeTypeTreeToString(tt) = ccall((:EnzymeTypeTreeToString, libEnzyme), Cstring, (CTypeTreeRef,), tt)
EnzymeStringFree(str) = ccall((:EnzymeStringFree, libEnzyme), Cvoid, (Cstring,), str)

struct CFnTypeInfo
    arguments::Ptr{CTypeTreeRef}
    ret::CTypeTreeRef

    known_values::Ptr{IntList}
end

@cenum(CDIFFE_TYPE,
  DFT_OUT_DIFF = 0,  # add differential to an output struct
  DFT_DUP_ARG = 1,   # duplicate the argument and store differential inside
  DFT_CONSTANT = 2,  # no differential
  DFT_DUP_NONEED = 3 # duplicate this argument and store differential inside,
                     # but don't need the forward
)

@cenum(CDerivativeMode,
  DEM_ForwardMode = 0,
  DEM_ReverseModePrimal = 1,
  DEM_ReverseModeGradient = 2,
  DEM_ReverseModeCombined = 3
)

# Create the derivative function itself.
#  \p todiff is the function to differentiate
#  \p retType is the activity info of the return
#  \p constant_args is the activity info of the arguments
#  \p returnValue is whether the primal's return should also be returned
#  \p dretUsed is whether the shadow return value should also be returned
#  \p additionalArg is the type (or null) of an additional type in the signature
#  to hold the tape.
#  \p typeInfo is the type info information about the calling context
#  \p _uncacheable_args marks whether an argument may be rewritten before loads in
#  the generated function (and thus cannot be cached).
#  \p augmented is the data structure created by prior call to an augmented forward
#  pass
#  \p AtomicAdd is whether to perform all adjoint updates to memory in an atomic way
#  \p PostOpt is whether to perform basic optimization of the function after synthesis
function EnzymeCreatePrimalAndGradient(logic, todiff, retType, constant_args, TA, 
                                       returnValue, dretUsed, mode, width, additionalArg, 
                                       forceAnonymousTape, typeInfo,
                                       uncacheable_args, augmented, atomicAdd)
    freeMemory = true
    ccall((:EnzymeCreatePrimalAndGradient, libEnzyme), LLVMValueRef, 
        (EnzymeLogicRef, LLVMValueRef, CDIFFE_TYPE, Ptr{CDIFFE_TYPE}, Csize_t,
         EnzymeTypeAnalysisRef, UInt8, UInt8, CDerivativeMode, Cuint, UInt8, LLVMTypeRef, UInt8, CFnTypeInfo,
         Ptr{UInt8}, Csize_t, EnzymeAugmentedReturnPtr, UInt8),
        logic, todiff, retType, constant_args, length(constant_args), TA, returnValue,
        dretUsed, mode, width, freeMemory, additionalArg, forceAnonymousTape, typeInfo, uncacheable_args, length(uncacheable_args),
        augmented, atomicAdd)
end

function EnzymeCreateForwardDiff(logic, todiff, retType, constant_args, TA, 
                                       returnValue, mode, width, additionalArg, typeInfo,
                                       uncacheable_args)
    freeMemory = true
    aug = C_NULL
    ccall((:EnzymeCreateForwardDiff, libEnzyme), LLVMValueRef, 
        (EnzymeLogicRef, LLVMValueRef, CDIFFE_TYPE, Ptr{CDIFFE_TYPE}, Csize_t,
         EnzymeTypeAnalysisRef, UInt8, CDerivativeMode, UInt8, Cuint, LLVMTypeRef, CFnTypeInfo,
         Ptr{UInt8}, Csize_t, EnzymeAugmentedReturnPtr),
        logic, todiff, retType, constant_args, length(constant_args), TA, returnValue,
        mode, freeMemory, width, additionalArg, typeInfo, uncacheable_args, length(uncacheable_args), aug)
end

# Create an augmented forward pass.
#  \p todiff is the function to differentiate
#  \p retType is the activity info of the return
#  \p constant_args is the activity info of the arguments
#  \p returnUsed is whether the primal's return should also be returned
#  \p typeInfo is the type info information about the calling context
#  \p _uncacheable_args marks whether an argument may be rewritten before loads in
#  the generated function (and thus cannot be cached).
#  \p forceAnonymousTape forces the tape to be an i8* rather than the true tape structure
#  \p AtomicAdd is whether to perform all adjoint updates to memory in an atomic way
#  \p PostOpt is whether to perform basic optimization of the function after synthesis
function EnzymeCreateAugmentedPrimal(logic, todiff, retType, constant_args, TA,  returnUsed,
                                     shadowReturnUsed,
                                     typeInfo, uncacheable_args, forceAnonymousTape, width, atomicAdd)
    ccall((:EnzymeCreateAugmentedPrimal, libEnzyme), EnzymeAugmentedReturnPtr, 
        (EnzymeLogicRef, LLVMValueRef, CDIFFE_TYPE, Ptr{CDIFFE_TYPE}, Csize_t, 
         EnzymeTypeAnalysisRef, UInt8, UInt8, 
         CFnTypeInfo, Ptr{UInt8}, Csize_t, UInt8, Cuint, UInt8),
        logic, todiff, retType, constant_args, length(constant_args), TA,  returnUsed,
        shadowReturnUsed,
        typeInfo, uncacheable_args, length(uncacheable_args), forceAnonymousTape, width, atomicAdd)
end

# typedef uint8_t (*CustomRuleType)(int /*direction*/, CTypeTreeRef /*return*/,
#                                   CTypeTreeRef * /*args*/,
#                                   struct IntList * /*knownValues*/,
#                                   size_t /*numArgs*/, LLVMValueRef);
const CustomRuleType = Ptr{Cvoid}

function CreateTypeAnalysis(logic, rulenames, rules)
    @assert length(rulenames) == length(rules)
    ccall((:CreateTypeAnalysis, libEnzyme), EnzymeTypeAnalysisRef, (EnzymeLogicRef, Ptr{Cstring}, Ptr{CustomRuleType}, Csize_t), logic, rulenames, rules, length(rules))
end

function ClearTypeAnalysis(ta)
    ccall((:ClearTypeAnalysis, libEnzyme), Cvoid, (EnzymeTypeAnalysisRef,), ta)
end

function FreeTypeAnalysis(ta)
    ccall((:FreeTypeAnalysis, libEnzyme), Cvoid, (EnzymeTypeAnalysisRef,), ta)
end

function EnzymeAnalyzeTypes(ta, CTI, F)
    ccall((:EnzymeAnalyzeTypes, libEnzyme), EnzymeTypeAnalyzerRef, (EnzymeTypeAnalysisRef, CFnTypeInfo, LLVMValueRef), ta, CTI, F)
end
                             
const CustomShadowAlloc = Ptr{Cvoid}
const CustomShadowFree = Ptr{Cvoid}
EnzymeRegisterAllocationHandler(name, ahandle, fhandle) = ccall((:EnzymeRegisterAllocationHandler, libEnzyme), Cvoid, (Cstring, CustomShadowAlloc, CustomShadowFree), name, ahandle, fhandle)


const CustomAugmentedForwardPass = Ptr{Cvoid}
const CustomForwardPass = Ptr{Cvoid}
const CustomReversePass = Ptr{Cvoid}
EnzymeRegisterCallHandler(name, fwdhandle, revhandle) = ccall((:EnzymeRegisterCallHandler, libEnzyme), Cvoid, (Cstring, CustomAugmentedForwardPass, CustomReversePass), name, fwdhandle, revhandle)
EnzymeRegisterFwdCallHandler(name, fwdhandle) = ccall((:EnzymeRegisterFwdCallHandler, libEnzyme), Cvoid, (Cstring, CustomForwardPass), name, fwdhandle)

EnzymeSetCalledFunction(ci::LLVM.CallInst, fn::LLVM.Function, toremove) = ccall((:EnzymeSetCalledFunction, libEnzyme), Cvoid, (LLVMValueRef, LLVMValueRef, Ptr{Int64}, Int64), ci, fn, toremove, length(toremove))
EnzymeCloneFunctionWithoutReturnOrArgs(fn::LLVM.Function, keepret, args) = ccall((:EnzymeCloneFunctionWithoutReturnOrArgs, libEnzyme), LLVMValueRef, (LLVMValueRef,UInt8,Ptr{Int64}, Int64), fn, keepret, args, length(args))
EnzymeGetShadowType(width, T) = ccall((:EnzymeGetShadowType, libEnzyme), LLVMTypeRef, (UInt64,LLVMTypeRef), width, T)

EnzymeGradientUtilsReplaceAWithB(gutils, a, b) = ccall((:EnzymeGradientUtilsReplaceAWithB, libEnzyme), Cvoid, (EnzymeGradientUtilsRef,LLVMValueRef, LLVMValueRef), gutils, a, b)
EnzymeGradientUtilsErase(gutils, a) = ccall((:EnzymeGradientUtilsErase, libEnzyme), Cvoid, (EnzymeGradientUtilsRef,LLVMValueRef), gutils, a)
EnzymeGradientUtilsGetMode(gutils) = ccall((:EnzymeGradientUtilsGetMode, libEnzyme), CDerivativeMode, (EnzymeGradientUtilsRef,), gutils)
EnzymeGradientUtilsGetWidth(gutils) = ccall((:EnzymeGradientUtilsGetWidth, libEnzyme), UInt64, (EnzymeGradientUtilsRef,), gutils)
EnzymeGradientUtilsNewFromOriginal(gutils, val) = ccall((:EnzymeGradientUtilsNewFromOriginal, libEnzyme), LLVMValueRef, (EnzymeGradientUtilsRef, LLVMValueRef), gutils, val)
EnzymeGradientUtilsSetDebugLocFromOriginal(gutils, val, orig) = ccall((:EnzymeGradientUtilsSetDebugLocFromOriginal, libEnzyme), Cvoid, (EnzymeGradientUtilsRef, LLVMValueRef, LLVMValueRef), gutils, val, orig)
EnzymeGradientUtilsLookup(gutils, val, B) = ccall((:EnzymeGradientUtilsLookup, libEnzyme), LLVMValueRef, (EnzymeGradientUtilsRef, LLVMValueRef, LLVM.API.LLVMBuilderRef), gutils, val, B)
EnzymeGradientUtilsInvertPointer(gutils, val, B) = ccall((:EnzymeGradientUtilsInvertPointer, libEnzyme), LLVMValueRef, (EnzymeGradientUtilsRef, LLVMValueRef, LLVM.API.LLVMBuilderRef), gutils, val, B)
EnzymeGradientUtilsDiffe(gutils, val, B) = ccall((:EnzymeGradientUtilsDiffe, libEnzyme), LLVMValueRef, (EnzymeGradientUtilsRef, LLVMValueRef, LLVM.API.LLVMBuilderRef), gutils, val, B)
EnzymeGradientUtilsAddToDiffe(gutils, val, diffe, B, T) = ccall((:EnzymeGradientUtilsAddToDiffe, libEnzyme), Cvoid, (EnzymeGradientUtilsRef, LLVMValueRef, LLVMValueRef, LLVM.API.LLVMBuilderRef, LLVMTypeRef), gutils, val, diffe, B, T)
function EnzymeGradientUtilsAddToInvertedPointerDiffeTT(gutils, orig, origVal, vd, size, origptr, prediff, B, align, premask) 
    ccall((:EnzymeGradientUtilsAddToInvertedPointerDiffeTT, libEnzyme), Cvoid, (EnzymeGradientUtilsRef, LLVMValueRef, LLVMValueRef, CTypeTreeRef, Cuint, LLVMValueRef, LLVMValueRef, LLVM.API.LLVMBuilderRef, Cuint, LLVMValueRef), gutils, orig, origVal, vd, size, origptr, prediff, B, align, premask)
end

EnzymeGradientUtilsSetDiffe(gutils, val, diffe, B) = ccall((:EnzymeGradientUtilsSetDiffe, libEnzyme), Cvoid, (EnzymeGradientUtilsRef, LLVMValueRef, LLVMValueRef, LLVM.API.LLVMBuilderRef), gutils, val, diffe, B)
EnzymeGradientUtilsIsConstantValue(gutils, val) = ccall((:EnzymeGradientUtilsIsConstantValue, libEnzyme), UInt8, (EnzymeGradientUtilsRef, LLVMValueRef), gutils, val)
EnzymeGradientUtilsIsConstantInstruction(gutils, val) = ccall((:EnzymeGradientUtilsIsConstantInstruction, libEnzyme), UInt8, (EnzymeGradientUtilsRef, LLVMValueRef), gutils, val)
EnzymeGradientUtilsAllocationBlock(gutils) = ccall((:EnzymeGradientUtilsAllocationBlock, libEnzyme), LLVM.API.LLVMBasicBlockRef, (EnzymeGradientUtilsRef,), gutils)

EnzymeGradientUtilsTypeAnalyzer(gutils) = ccall((:EnzymeGradientUtilsTypeAnalyzer, libEnzyme), EnzymeTypeAnalyzerRef, (EnzymeGradientUtilsRef,), gutils)

EnzymeGradientUtilsAllocAndGetTypeTree(gutils, val) = ccall((:EnzymeGradientUtilsAllocAndGetTypeTree, libEnzyme), CTypeTreeRef, (EnzymeGradientUtilsRef,LLVMValueRef), gutils, val)
    
EnzymeGradientUtilsGetUncacheableArgs(gutils, orig, uncacheable, size) = ccall((:EnzymeGradientUtilsGetUncacheableArgs, libEnzyme), Cvoid, (EnzymeGradientUtilsRef,LLVMValueRef, Ptr{UInt8}, UInt64), gutils, orig, uncacheable, size)

EnzymeGradientUtilsGetDiffeType(gutils, op, isforeign) = ccall((:EnzymeGradientUtilsGetDiffeType, libEnzyme), CDIFFE_TYPE, (EnzymeGradientUtilsRef,LLVMValueRef, UInt8), gutils, op, isforeign)
    
EnzymeGradientUtilsGetReturnDiffeType(gutils, orig, needsPrimalP, needsShadowP) = ccall((:EnzymeGradientUtilsGetReturnDiffeType, libEnzyme), CDIFFE_TYPE, (EnzymeGradientUtilsRef,LLVMValueRef, Ptr{UInt8}, Ptr{UInt8}), gutils, orig, needsPrimalP, needsShadowP)

EnzymeGradientUtilsSubTransferHelper(gutils, mode, secretty, intrinsic, dstAlign, srcAlign, offset, dstConstant, origdst, srcConstant, origsrc, length, isVolatile, MTI, allowForward, shadowsLookedUp) = ccall((:EnzymeGradientUtilsSubTransferHelper, libEnzyme),
	Cvoid,
    ( EnzymeGradientUtilsRef, CDerivativeMode, LLVMTypeRef, UInt64, UInt64, UInt64, UInt64, UInt8, LLVMValueRef, UInt8, LLVMValueRef, LLVMValueRef, LLVMValueRef, LLVMValueRef, UInt8, UInt8),
	gutils, mode, secretty, intrinsic, dstAlign, srcAlign, offset, dstConstant, origdst, srcConstant, origsrc, length, isVolatile, MTI, allowForward, shadowsLookedUp)
        
EnzymeGradientUtilsCallWithInvertedBundles(gutils, func, argvs, argc, orig, valTys, valCnt, B, lookup) = ccall((:EnzymeGradientUtilsCallWithInvertedBundles, libEnzyme), LLVMValueRef, (EnzymeGradientUtilsRef,LLVMValueRef, Ptr{LLVMValueRef}, UInt64, LLVMValueRef, Ptr{CValueType}, UInt64, LLVM.API.LLVMBuilderRef, UInt8), gutils, func, argvs, argc, orig, valTys, valCnt, B, lookup)

function sub_transfer(gutils, mode, secretty, intrinsic, dstAlign, srcAlign, offset, dstConstant, origdst, srcConstant, origsrc, length, isVolatile, MTI, allowForward, shadowsLookedUp)
    GC.@preserve secretty begin
        if secretty === nothing
            secretty = Base.unsafe_convert(LLVMTypeRef, C_NULL)
        else
            secretty = Base.unsafe_convert(LLVMTypeRef, secretty)
        end

        EnzymeGradientUtilsSubTransferHelper(gutils, mode, secretty, intrinsic, dstAlign, srcAlign, offset, dstConstant, origdst, srcConstant, origsrc, length, isVolatile, MTI, allowForward, shadowsLookedUp)
    end
end

function CreateLogic(postOpt=false)
    ccall((:CreateEnzymeLogic, libEnzyme), EnzymeLogicRef, (UInt8,), postOpt)
end

EnzymeLogicErasePreprocessedFunctions(logic) = ccall((:EnzymeLogicErasePreprocessedFunctions, libEnzyme), Cvoid, (EnzymeLogicRef,), logic)

function ClearLogic(logic)
    ccall((:ClearEnzymeLogic, libEnzyme), Cvoid, (EnzymeLogicRef,), logic)
end

function FreeLogic(logic)
    ccall((:FreeEnzymeLogic, libEnzyme), Cvoid, (EnzymeLogicRef,), logic)
end

function EnzymeExtractReturnInfo(ret, data, existed)
    @assert length(data) == length(existed)
    ccall((:EnzymeExtractReturnInfo, libEnzyme),
           Cvoid, (EnzymeAugmentedReturnPtr, Ptr{Int64}, Ptr{UInt8}, Csize_t),
           ret, data, existed, length(data))
end

function EnzymeExtractFunctionFromAugmentation(ret)
    ccall((:EnzymeExtractFunctionFromAugmentation, libEnzyme), LLVMValueRef, (EnzymeAugmentedReturnPtr,), ret)
end


function EnzymeExtractTapeTypeFromAugmentation(ret)
    ccall((:EnzymeExtractTapeTypeFromAugmentation, libEnzyme), LLVMTypeRef, (EnzymeAugmentedReturnPtr,), ret)
end

function EnzymeExtractUnderlyingTapeTypeFromAugmentation(ret)
    ccall((:EnzymeExtractUnderlyingTapeTypeFromAugmentation, libEnzyme), LLVMTypeRef, (EnzymeAugmentedReturnPtr,), ret)
end

import Libdl
function EnzymeSetCLBool(name, val)
    handle = Libdl.dlopen(libEnzyme)
    ptr = Libdl.dlsym(handle, name)
    ccall((:EnzymeSetCLBool, libEnzyme), Cvoid, (Ptr{Cvoid}, UInt8), ptr, val)
end
function EnzymeGetCLBool(ptr)
    ccall((:EnzymeGetCLBool, libEnzyme), UInt8, (Ptr{Cvoid},), ptr)
end
# void EnzymeSetCLInteger(void *, int64_t);

function zcache!(val)
    ptr = cglobal((:EnzymeZeroCache, libEnzyme))
    ccall((:EnzymeSetCLBool, libEnzyme), Cvoid, (Ptr{Cvoid}, UInt8), ptr, val)
end

function printperf!(val)
    ptr = cglobal((:EnzymePrintPerf, libEnzyme))
    ccall((:EnzymeSetCLBool, libEnzyme), Cvoid, (Ptr{Cvoid}, UInt8), ptr, val)
end

function printdiffuse!(val)
    ptr = cglobal((:EnzymePrintDiffUse, libEnzyme))
    ccall((:EnzymeSetCLBool, libEnzyme), Cvoid, (Ptr{Cvoid}, UInt8), ptr, val)
end

function printtype!(val)
    ptr = cglobal((:EnzymePrintType, libEnzyme))
    ccall((:EnzymeSetCLBool, libEnzyme), Cvoid, (Ptr{Cvoid}, UInt8), ptr, val)
end

function printactivity!(val)
    ptr = cglobal((:EnzymePrintActivity, libEnzyme))
    ccall((:EnzymeSetCLBool, libEnzyme), Cvoid, (Ptr{Cvoid}, UInt8), ptr, val)
end

function printall!(val)
    ptr = cglobal((:EnzymePrint, libEnzyme))
    ccall((:EnzymeSetCLBool, libEnzyme), Cvoid, (Ptr{Cvoid}, UInt8), ptr, val)
end

function printunnecessary!(val)
    ptr = cglobal((:EnzymePrintUnnecessary, libEnzyme))
    ccall((:EnzymeSetCLBool, libEnzyme), Cvoid, (Ptr{Cvoid}, UInt8), ptr, val)
end

function inlineall!(val)
    ptr = cglobal((:EnzymeInline, libEnzyme))
    ccall((:EnzymeSetCLBool, libEnzyme), Cvoid, (Ptr{Cvoid}, UInt8), ptr, val)
end

function maxtypeoffset!(val)
    ptr = cglobal((:MaxTypeOffset, libEnzyme))
    ccall((:EnzymeSetCLInteger, libEnzyme), Cvoid, (Ptr{Cvoid}, Int64), ptr, val)
end

function looseTypeAnalysis!(val)
    ptr = cglobal((:looseTypeAnalysis, libEnzyme))
    ccall((:EnzymeSetCLInteger, libEnzyme), Cvoid, (Ptr{Cvoid}, UInt8), ptr, val)
end

function strictAliasing!(val)
    ptr = cglobal((:EnzymeStrictAliasing, libEnzyme))
    ccall((:EnzymeSetCLInteger, libEnzyme), Cvoid, (Ptr{Cvoid}, UInt8), ptr, val)
end

function fast_math!(val)
    ptr = cglobal((:EnzymeFastMath, libEnzyme))
    ccall((:EnzymeSetCLInteger, libEnzyme), Cvoid, (Ptr{Cvoid}, UInt8), ptr, val)
end

function strong_zero!(val)
    ptr = cglobal((:EnzymeStrongZero, libEnzyme))
    ccall((:EnzymeSetCLInteger, libEnzyme), Cvoid, (Ptr{Cvoid}, UInt8), ptr, val)
end

"""
    runtimeActivity!(val::Bool)

Enzyme runs an activity analysis which deduces which values, instructions, etc
are necessary to be differentiated and therefore involved in the differentiation
procedure. This runs at compile time. However, there may be implementation flaws
in this analysis that means that Enzyme cannot deduce that an inactive (const)
value is actually const. Alternatively, there may be some data which is conditionally
active, depending on which runtime branch is taken. In these cases Enzyme conservatively
presumes the value is active.

However, in certain cases, an insufficiently aggressive activity analysis may result
in derivative errors -- for example by mistakenly using the primal (const) argument
and mistaking it for the duplicated shadow. As a result this may result in incorrect
results, or accidental updates to the primal.

This flag enables runntime activity which tells all load/stores to check at runtime
whether the value they are updating is indeed active (in addition to the compile-time
activity analysis). This will remedy these such errors, but at a performance penalty
of performing such checks.

It is on the Enzyme roadmap to add a PotentiallyDuplicated style activity, in addition
to the current Const and Duplicated styles that will disable the need for this,
which does  not require the check when a value is guaranteed active, but still supports
runtime-based activity information.

This function takes an argument to set the runtime activity value, true means it is on,
and false means off. By default it is off.
"""
function runtimeActivity!(val::Bool)
    ptr = cglobal((:EnzymeRuntimeActivityCheck, libEnzyme))
    ccall((:EnzymeSetCLInteger, libEnzyme), Cvoid, (Ptr{Cvoid}, UInt8), ptr, val)
end

"""
    runtimeActivity()

Gets the current value of the runtime activity. See [`runtimeActivity!`](@ref) for
more information.
"""
function runtimeActivity()
    ptr = cglobal((:EnzymeRuntimeActivityCheck, libEnzyme))
    return EnzymeGetCLBool(ptr) != 0
end

function typeWarning!(val)
    ptr = cglobal((:EnzymeTypeWarning, libEnzyme))
    ccall((:EnzymeSetCLInteger, libEnzyme), Cvoid, (Ptr{Cvoid}, UInt8), ptr, val)
end

function instname!(val)
    ptr = cglobal((:EnzymeNameInstructions, libEnzyme))
    ccall((:EnzymeSetCLBool, libEnzyme), Cvoid, (Ptr{Cvoid}, UInt8), ptr, val)
end

function EnzymeRemoveTrivialAtomicIncrements(func)
    ccall((:EnzymeRemoveTrivialAtomicIncrements, libEnzyme), Cvoid, (LLVMValueRef,), func)
end

function EnzymeAddAttributorLegacyPass(PM)
    ccall((:EnzymeAddAttributorLegacyPass, libEnzyme),Cvoid,(LLVM.API.LLVMPassManagerRef,), PM)
end

@cenum(ErrorType,
  ET_NoDerivative = 0,
  ET_NoShadow = 1,
  ET_IllegalTypeAnalysis = 2,
  ET_NoType = 3,
  ET_IllegalFirstPointer = 4,
  ET_InternalError = 5,
  ET_TypeDepthExceeded = 6,
  ET_MixedActivityError = 7,
  ET_IllegalReplaceFicticiousPHIs = 8
)

function EnzymeTypeAnalyzerToString(typeanalyzer)
    ccall((:EnzymeTypeAnalyzerToString, libEnzyme), Cstring, (EnzymeTypeAnalyzerRef,), typeanalyzer)
end

function EnzymeGradientUtilsInvertedPointersToString(gutils)
    ccall((:EnzymeGradientUtilsInvertedPointersToString, libEnzyme), Cstring, (Ptr{Cvoid},), gutils)
end

function EnzymeSetHandler(handler)
    ptr = cglobal((:CustomErrorHandler, libEnzyme), Ptr{Ptr{Cvoid}})
    unsafe_store!(ptr, handler)
end
function EnzymeSetSanitizeDerivatives(handler)
    ptr = cglobal((:EnzymeSanitizeDerivatives, libEnzyme), Ptr{Ptr{Cvoid}})
    unsafe_store!(ptr, handler)
end
function EnzymeSetRuntimeInactiveError(handler)
    ptr = cglobal((:CustomRuntimeInactiveError, libEnzyme), Ptr{Ptr{Cvoid}})
    unsafe_store!(ptr, handler)
end
function EnzymeHasCustomInactiveSupport()
    try
        EnzymeSetRuntimeInactiveError(C_NULL)
    catch
        return false
    end
    return true
end

function EnzymeSetPostCacheStore(handler)
    ptr = cglobal((:EnzymePostCacheStore, libEnzyme), Ptr{Ptr{Cvoid}})
    unsafe_store!(ptr, handler)
end
function EnzymeSetUndefinedValueForType(handler)
    ptr = cglobal((:EnzymeUndefinedValueForType, libEnzyme), Ptr{Ptr{Cvoid}})
    unsafe_store!(ptr, handler)
end
function EnzymeSetDefaultTapeType(handler)
    ptr = cglobal((:EnzymeDefaultTapeType, libEnzyme), Ptr{Ptr{Cvoid}})
    unsafe_store!(ptr, handler)
end
function EnzymeSetCustomAllocator(handler)
    ptr = cglobal((:CustomAllocator, libEnzyme), Ptr{Ptr{Cvoid}})
    unsafe_store!(ptr, handler)
end
function EnzymeSetCustomDeallocator(handler)
    ptr = cglobal((:CustomDeallocator, libEnzyme), Ptr{Ptr{Cvoid}})
    unsafe_store!(ptr, handler)
end
function EnzymeSetCustomZero(handler)
    ptr = cglobal((:CustomZero, libEnzyme), Ptr{Ptr{Cvoid}})
    unsafe_store!(ptr, handler)
end
function EnzymeSetFixupReturn(handler)
    ptr = cglobal((:EnzymeFixupReturn, libEnzyme), Ptr{Ptr{Cvoid}})
    unsafe_store!(ptr, handler)
end

function EnzymeHasCustomAllocatorSupport()
    try
        EnzymeSetCustomAllocator(C_NULL)
        EnzymeSetCustomDeallocator(C_NULL)
    catch
        return false
    end
    return true
end

function __init__()
    ptr = cglobal((:EnzymeJuliaAddrLoad, libEnzyme))
    val = true
    ccall((:EnzymeSetCLBool, libEnzyme), Cvoid, (Ptr{Cvoid}, UInt8), ptr, val)
    zcache!(true)
end

function moveBefore(i1, i2, BR)
    ccall((:EnzymeMoveBefore, libEnzyme),Cvoid,(LLVM.API.LLVMValueRef,LLVM.API.LLVMValueRef, LLVM.API.LLVMBuilderRef), i1, i2, BR)
end

function EnzymeCloneFunctionDISubprogramInto(i1, i2)
    ccall((:EnzymeCloneFunctionDISubprogramInto, libEnzyme),Cvoid,(LLVM.API.LLVMValueRef,LLVM.API.LLVMValueRef), i1, i2)
end

function EnzymeCopyMetadata(i1, i2)
    ccall((:EnzymeCopyMetadata, libEnzyme),Cvoid,(LLVM.API.LLVMValueRef,LLVM.API.LLVMValueRef), i1, i2)
end

function SetMustCache!(i1)
    ccall((:EnzymeSetMustCache, libEnzyme),Cvoid,(LLVM.API.LLVMValueRef,), i1)
end

function SetForMemSet!(i1)
    ccall((:EnzymeSetForMemSet, libEnzyme),Cvoid,(LLVM.API.LLVMValueRef,), i1)
end

function HasFromStack(i1)
    ccall((:EnzymeHasFromStack, libEnzyme),UInt8,(LLVM.API.LLVMValueRef,), i1) != 0
end

function AddPreserveNVVMPass!(pm, i8)
    ccall((:AddPreserveNVVMPass, libEnzyme),Cvoid,(LLVM.API.LLVMPassManagerRef,UInt8), pm, i8)
end

function EnzymeReplaceFunctionImplementation(mod)
    ccall((:EnzymeReplaceFunctionImplementation, libEnzyme),Cvoid,(LLVM.API.LLVMModuleRef,), mod)
end

EnzymeAllocaType(al) = LLVM.LLVMType(ccall((:EnzymeAllocaType, libEnzyme), LLVM.API.LLVMTypeRef, (LLVM.API.LLVMValueRef,), al))

EnzymeAttributeKnownFunctions(f) = ccall((:EnzymeAttributeKnownFunctions, libEnzyme), Cvoid, (LLVM.API.LLVMValueRef,), f)

EnzymeAnonymousAliasScopeDomain(str, ctx) = LLVM.Metadata(ccall((:EnzymeAnonymousAliasScopeDomain, libEnzyme), LLVM.API.LLVMMetadataRef, (Cstring,LLVMContextRef), str, ctx))
EnzymeAnonymousAliasScope(dom::LLVM.Metadata, str) = LLVM.Metadata(ccall((:EnzymeAnonymousAliasScope, libEnzyme), LLVM.API.LLVMMetadataRef, (LLVM.API.LLVMMetadataRef,Cstring), dom.ref, str))
EnzymeFixupJuliaCallingConvention(f) = ccall((:EnzymeFixupJuliaCallingConvention, libEnzyme), Cvoid, (LLVM.API.LLVMValueRef,), f)

e_extract_value!(builder, AggVal, Index, Name::String="") =
  GC.@preserve Index begin
    LLVM.Value(ccall((:EnzymeBuildExtractValue, libEnzyme), LLVM.API.LLVMValueRef,  (LLVM.API.LLVMBuilderRef, LLVM.API.LLVMValueRef, Ptr{Cuint}, Cuint, Cstring), builder, AggVal, Index, length(Index), Name))
  end

e_insert_value!(builder, AggVal, EltVal, Index, Name::String="") =
  GC.@preserve Index begin
    LLVM.Value(ccall((:EnzymeBuildInsertValue, libEnzyme), LLVM.API.LLVMValueRef,  (LLVM.API.LLVMBuilderRef, LLVM.API.LLVMValueRef, LLVM.API.LLVMValueRef, Ptr{Cuint}, Cuint, Cstring), builder, AggVal, EltVal, Index, length(Index), Name))
  end

end
