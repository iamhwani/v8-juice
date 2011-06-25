#!/bin/bash
########################################################################
# Generates code for the the # v8::convert API (and friends).
count=${1-0}

test "$count" -gt 0 || {
    echo "Usage: $0 NUMBER (>=1) COMMAND(s)"
cat <<EOF
Commands:
  SignatureBase
  FunctionSignature
  MethodSignature
  ConstMethodSignature
  ArgsToMethodForwarder
  ArgsToFunctionForwarder
EOF
    echo "Generates specializations for operations taking exactly NUMBER argumnents."
    exit 1
}
shift

ValueHandle="v8::Handle<v8::Value>"
tmplsig="typename WrappedType, typename RV, "
ttlist="WrappedType, RV,"
tmplsigV="typename WrappedType, void, "
aTDecl="" # typename A0, typename A1,...
aTParam="" # A0, A1 ...
castCalls="" # CastFromJS<A0>(argv[0]), ...
castTypedefs="" # typedef ArgCaster<A#> AC#, ...
castInits="" # AC# ac#; ...
callArgs="" # a0, ... aN
sigTypeDecls="" # SignatureType::ArgType# A#...
at=0

########################################################
# must be called first to populate the shared vars
function makeLists()
{
    for (( at = 0; at < count; at = at + 1)); do
    #echo "at=$at"
	local AT="A${at}"
	tmplsig="${tmplsig} typename ${AT},"
	ttlist="${ttlist} ${AT},"
	tmplsigV="${tmplsigV} ${AT},"
	aTDecl="${aTDecl} typename ${AT}"
	aTParam="${aTParam} ${AT}"
	callArgs="${callArgs}${AT}"
        #sigTypeDecls="${sigTypeDecls}typedef typename SignatureType::ArgType${at} ${AT};"
        sigTypeDecls="${sigTypeDecls}typedef typename tmp::TypeAt< SignatureTypeList<Sig>, ${at}>::Type ${AT};\n"
	#castCalls="${castCalls} CastFromJS< ${AT} >(argv[${at}])"
        castTypedefs="${castTypedefs} typedef ArgCaster<${AT}> AC${at};\n"
        #castInits="${castInits} AC${at} ac${at};"
        #castCalls="${castCalls} ac${at}.ToNative(argv[${at}])"
        castInits="${castInits} AC${at} ac${at}; A${at} arg${at}(ac${at}.ToNative(argv[${at}]));\n"
        castCalls="${castCalls} arg${at}"
	test $at -ne $((count-1)) && {
	    aTDecl="${aTDecl}, "
	    aTParam="${aTParam}, "
	    castCalls="${castCalls}, "
        callArgs="${callArgs}, "
	}
    done
    #tmplsig="${tmplsig} RV (WrappedType::*Func)(${aTParam})";
    funcSig="(WrappedType::*Func)(${aTParam}) "
    tmplsig="typename WrappedType, typename RV, ${aTDecl}, RV ${funcSig}";
    tmplsigV="typename WrappedType, ${aTDecl}, void ${funcSig}";
    tmplspecV="WrappedType, void, ${aTParam}, void ${funcSig}"
    castOps="${castTypedefs} ${castInits}"
}

function mycat()
{
    perl -pe 's|\\n|\n\t\t|g'
}

#######################################################
# Creates CtorForwarder specializations.
function makeCtorForwarder()
{

    local err_too_few_args="CtorForwarder<T,${count}>::Ctor() expects at least ${count} JS arguments!"
    local err_exception="CtorForwarder<T,${count}>::Ctor() Native ctor threw an unknown native exception type!"

    mycat <<EOF
namespace Detail {
template <>
struct CtorForwarderProxy<${count}> // todo: subclass SignatureTypeList<Sig>
{
    enum { Arity = ${count} };
    template <typename Sig>
    static typename SignatureTypeList<Sig>::ReturnType Ctor( ::v8::Arguments const & argv )
    {
        if( argv.Length() < Arity )
        {
            throw std::range_error("${err_too_few_args}");
        }
        else
        {
            typedef typename SignatureTypeList<Sig>::ReturnType Type_;
            typedef typename TypeInfo<Type_>::Type Type;
            ${sigTypeDecls}
            ${castTypedefs}
            ${castInits}
            return new Type( ${castCalls} );
        }
    }
};
}
EOF

: <<EOF
/** Specialization for ${count} arguments. */
template <typename Sig>
struct CtorForwarderProxy<Sig> // todo: subclass SignatureTypeList<Sig>
{
    typedef SignatureTypeList<Sig> STL;
    typedef typename STL::ReturnType Type_;
    enum { Arity = STL::Arity };
    //enum { Arity = ${count} };
    typedef typename TypeInfo<Type_>::Type Type;
    typedef typename TypeInfo<Type_>::NativeHandle NativeHandle;
    static NativeHandle Ctor( ::v8::Arguments const & argv )
    {
        if( argv.Length() < Arity )
        {
            throw std::range_error("${err_too_few_args}");
        }
        else
        {
            ${sigTypeDecls}
            ${castTypedefs}
            ${castInits}
            return new Type( ${castCalls} );
        }
    }

};

EOF
} # makeCtorForwarder

########################################################################
# Create SignatureBase<> and friends...
function makeSignatureBase()
{
    echo "Don't call makeSignatureBase()! It's not needed anymore :-D" 1>&2
    exit 1
    mycat <<EOF
template <typename RV, ${aTDecl} >
struct SignatureBase< RV (${aTParam}) > : SignatureBase< RV, ${count} >
{
    typedef RV (*FunctionType)(${aTParam});
EOF
    local i=0
    while [ $i -lt $count ]; do
        #echo -e "\ttypedef A${i} ArgType${i};"
        i=$((i + 1))
    done
    
mycat <<EOF
};

template <typename RV, ${aTDecl} >
struct SignatureBase< RV (*)(${aTParam}), ${count} >
  : SignatureBase< RV (${aTParam}), ${count} >
{};

EOF
}


########################################################################
# Create FunctionSignature<> and friends...
function makeFunctionSignature()
{
    mycat <<EOF
template <typename RV, ${aTDecl} >
struct FunctionSignature< RV (${aTParam}) > : SignatureBase< RV (${aTParam}) >
{
    typedef RV (*FunctionType)(${aTParam});
EOF
    local i=0
    while [ $i -lt $count ]; do
        #echo -e "\ttypedef A${i} ArgType${i};"
        i=$((i + 1))
    done
    
mycat <<EOF
};

template <typename RV, ${aTDecl} >
struct FunctionSignature< RV (*)(${aTParam}) >
  : FunctionSignature< RV (${aTParam}) >
{};

EOF
}

########################################################################
# Create MethodSignature<> and friends...
function makeMethodSignature()
{
    mycat <<EOF

template <typename T, typename RV, ${aTDecl} >
struct MethodSignature< T, RV (${aTParam}) > : SignatureBase< RV (${aTParam}) >
{
    typedef T ClassType;
    typedef RV (T::*FunctionType)(${aTParam});
EOF
    local i=0
    while [ $i -lt $count ]; do
        #echo -e "\ttypedef A${i} ArgType${i};"
        i=$((i + 1))
    done
    
mycat <<EOF
};
template <typename T, typename RV, ${aTDecl} >
struct MethodSignature< T, RV (T::*)(${aTParam}) > :
    MethodSignature< T, RV (${aTParam}) >
{};


EOF
}

########################################################################
# Create ConstMethodSignature<> and friends...
# TODO: move this into makeMethodSignature.
function makeConstMethodSignature()
{
    mycat <<EOF
template <typename T, typename RV, ${aTDecl} >
struct ConstMethodSignature< T, RV (${aTParam}) > : SignatureBase< RV (${aTParam}) >
{
    typedef T ClassType;
    typedef RV (T::*FunctionType)(${aTParam}) const;
EOF
    local i=0
    while [ $i -lt $count ]; do
        #echo -e "\ttypedef A${i} ArgType${i};"
        i=$((i + 1))
    done
    
mycat <<EOF
};

template <typename T, typename RV, ${aTDecl} >
struct ConstMethodSignature< T, RV (${aTParam}) const > :
    ConstMethodSignature< T, RV (${aTParam}) >
{};


template <typename T, typename RV, ${aTDecl} >
struct ConstMethodSignature< T, RV (T::*)(${aTParam}) const > :
    ConstMethodSignature< T, RV (${aTParam}) >
{};
EOF

: <<EOF
template <typename T, typename RV, ${aTDecl} >
struct ConstMethodSignature< T, RV (T::*)(${aTParam}) > :
    ConstMethodSignature< T, RV (${aTParam}) >
{};

EOF

}


########################################################################
# Create FunctionToInCa<> and friends...
function makeFunctionToInCa()
{
    echo "Don't call makeFunctionToInCa()! It's not needed anymore :-D" 1>&2
    exit 1

    mycat <<EOF
namespace Detail {
template <typename Sig, typename FunctionSignature<Sig>::FunctionType Func, bool UnlockV8 >
struct FunctionToInCa< ${count}, Sig, Func, UnlockV8 > : FunctionPtr< Sig, Func >
{
    public:
        //typedef typename ParentType::SignatureType SignatureType;
        static ${ValueHandle} Call( Arguments const & argv )
        {
            typedef FunctionPtr<Sig, Func> ParentType;
            typedef ArgsToFunctionForwarder<ParentType::Arity, Sig, UnlockV8> Proxy;
            if( !argv.Length() || (argv.Length() < ParentType::Arity) )
            {
                return JS_THROW("This function requires at least ${count} arguments!");
            }
            return Proxy::Call( Func, argv );
        }
};
EOF

    mycat <<EOF
template <typename Sig, typename FunctionSignature<Sig>::FunctionType Func, bool UnlockV8>
struct FunctionToInCaVoid< ${count}, Sig, Func, UnlockV8 > : FunctionPtr< Sig, Func >
{
    public:
        //typedef typename ParentType::SignatureType SignatureType;
        static ${ValueHandle} Call( Arguments const & argv )
        {
            typedef FunctionPtr<Sig, Func> ParentType;
            typedef ArgsToFunctionForwarderVoid<ParentType::Arity, Sig, UnlockV8> Proxy;
            if( !argv.Length() || (argv.Length() < ParentType::Arity) )
            {
                return JS_THROW("This function requires at least ${count} arguments!");
            }
            Proxy::Call( Func, argv );
            return v8::Undefined();
        }
};
} // namespace
EOF
}

########################################################################
# Create MethodToInCa<> and friends...
function makeMethodToInCa_impl()
{
    local class=MethodToInCa
    local parent=MethodPtr
    local msig=MethodSignature
    local constness=""
    if [[ "x$1" = "xconst" ]]; then
        class=ConstMethodToInCa
        parent=ConstMethodPtr
        msig=ConstMethodSignature
        constness="const"
    fi
    mycat <<EOF
namespace Detail {
template <typename T, typename Sig,
typename ${msig}<T,Sig>::FunctionType Func, bool UnlockV8>
struct ${class}<T, ${count}, Sig, Func, UnlockV8 > : ${parent}< T, Sig, Func >
{
    private:
        //typedef typename ParentType::SignatureType SignatureType;
    public:
        static ${ValueHandle} Call( T ${constness} & self, Arguments const & argv )
        {
            typedef ${parent}<T, Sig, Func> ParentType;
            if( argv.Length() < ParentType::Arity )
            {
                return JS_THROW("This function requires at least ${count} arguments!");
            }
            ${sigTypeDecls}
            ${castTypedefs}
            ${castInits}
            return CastToJS( (self.*Func)( ${castCalls} ) );
        }
        static ${ValueHandle} Call( Arguments const & argv )
        {
            T ${constness} * self = CastFromJS<T>(argv.This());
            return self
                ? Call(*self, argv)
                : JS_THROW("CastFromJS<T>() returned NULL! Cannot find 'this' pointer!");
        }
};
EOF

    mycat <<EOF
template <typename T, typename Sig,
typename ${msig}<T,Sig>::FunctionType Func, bool UnlockV8>
struct ${class}Void< T, ${count}, Sig, Func, UnlockV8 > : ${parent}< T, Sig, Func >
{
    private:
        //typedef typename ParentType::SignatureType SignatureType;
    public:
        static ${ValueHandle} Call( T ${constness} & self, Arguments const & argv )
        {
            typedef ${parent}<T, Sig, Func> ParentType;
            if( argv.Length() < ParentType::Arity )
            {
                return JS_THROW("This function requires at least ${count} arguments!");
            }
            ${sigTypeDecls}
            ${castTypedefs}
            ${castInits}
            (self.*Func)( ${castCalls} );
            return v8::Undefined();
        }
        static ${ValueHandle} Call( Arguments const & argv )
        {
            T ${constness} * self = CastFromJS<T>(argv.This());
            return self
                ? Call(*self, argv)
                : JS_THROW("CastFromJS<T>() returned NULL! Cannot find 'this' pointer!");
        }
};
} // namespace
EOF
}
function makeMethodToInCa()
{
    makeMethodToInCa_impl
    makeMethodToInCa_impl const
}

########################################################################
# Generates ArgsToFunctionForwarder<>
function makeArgsToFunctionForwarder()
{

mycat <<EOF
namespace Detail {
    template <typename Sig, bool UnlockV8>
    struct ArgsToFunctionForwarder<${count},Sig,UnlockV8> : FunctionSignature<Sig>
    {
        typedef FunctionSignature<Sig> SignatureType;
        typedef typename SignatureType::FunctionType FunctionType;
        static ${ValueHandle} Call( FunctionType func, v8::Arguments const & argv )
        {
            typedef char AssertArity[ SignatureType::Arity == ${count} ? 1 : -1];
            ${sigTypeDecls}
            ${castTypedefs}
            ${castInits}
            typedef typename SignatureType::ReturnType RV;
            V8Unlocker<UnlockV8> unlocker;
            RV rv( (*func)( ${castCalls} ) );
            unlocker.Dispose();
            return CastToJS( rv );
        }
    };

    template <typename Sig, bool UnlockV8>
    struct ArgsToFunctionForwarderVoid<${count},Sig,UnlockV8> : FunctionSignature<Sig>
    {
        typedef FunctionSignature<Sig> SignatureType;
        typedef typename SignatureType::FunctionType FunctionType;
        static ${ValueHandle} Call( FunctionType func, v8::Arguments const & argv )
        {
            typedef char AssertArity[ SignatureType::Arity == ${count} ? 1 : -1];
            ${sigTypeDecls}
            ${castTypedefs}
            ${castInits}
            {
                V8Unlocker<UnlockV8> const unlocker();
                (*func)( ${castCalls} );
            }
            return v8::Undefined();
        }
    };
}
EOF

:<<EOF
    template <typename Sig>
    struct ArgsToFunctionForwarder<${count},Sig,false> : FunctionSignature<Sig>
    {
    public:
        typedef FunctionSignature<Sig> SignatureType;
        typedef typename SignatureType::FunctionType FunctionType;
        static ${ValueHandle} Call( FunctionType func, v8::Arguments const & argv )
        {
            ${sigTypeDecls}
            ${castTypedefs}
            ${castInits}
            return CastToJS( (*func)( ${castCalls} ) );
        }
    };
    template <typename Sig>
    struct ArgsToFunctionForwarder<${count},Sig,true> : FunctionSignature<Sig>
    {
        typedef FunctionSignature<Sig> SignatureType;
        typedef typename SignatureType::FunctionType FunctionType;
        static ${ValueHandle} Call( FunctionType func, v8::Arguments const & argv )
        {
            ${sigTypeDecls}
            ${castTypedefs}
            ${castInits}
            typedef typename SignatureType::ReturnType RV;
            V8Unlocker<true> unlocker;
            RV rv( (*func)( ${castCalls} ) );
            unlocker.Dispose();
            return CastToJS( rv );
        }
    };
EOF

}

########################################################################
# Generates ArgsToMethodForwarder<>
function makeArgsToMethodForwarder_impl()
{
    local class=ArgsToMethodForwarder
    local parent=MethodSignature
    local constness=""
    if [[ "x$1" = "xconst" ]]; then
        parent=ConstMethodSignature
        class=ArgsToConstMethodForwarder
        constness="const"
    fi
mycat <<EOF
namespace Detail {
    template <typename T, typename Sig>
    struct ${class}<T, ${count},Sig> : ${parent}<T,Sig>
    {
        typedef ${parent}<T,Sig> SignatureType;
        typedef typename SignatureType::FunctionType FunctionType;
        static ${ValueHandle} Call( T ${constness} & self, FunctionType func, Arguments const & argv )
        {
            ${sigTypeDecls}
            ${castTypedefs}
            ${castInits}
            return CastToJS( (self.*func)( ${castCalls} ) );
        }
        static ${ValueHandle} Call( FunctionType func, Arguments const & argv )
        {
            T ${constness} * self = CastFromJS<T>(argv.This());
            return self
                ? Call(*self, func, argv)
                : JS_THROW("CastFromJS<T>() returned NULL! Cannot find 'this' pointer!");
        }
    };

    template <typename T, typename Sig>
    struct ${class}Void<T, ${count},Sig> : ${parent}<T,Sig>
    {
        typedef ${parent}<T,Sig> SignatureType;
        typedef typename SignatureType::FunctionType FunctionType;
        static ${ValueHandle} Call( T ${constness} & self, FunctionType func, Arguments const & argv )
        {
            ${sigTypeDecls}
            ${castTypedefs}
            ${castInits}
            (self.*func)( ${castCalls} );
            return v8::Undefined();
        }
        static ${ValueHandle} Call( FunctionType func, Arguments const & argv )
        {
            T ${constness} * self = CastFromJS<T>(argv.This());
            return self
                ? Call(*self, func, argv)
                : JS_THROW("CastFromJS<T>() returned NULL! Cannot find 'this' pointer!");
        }
    };
}
EOF
}

function makeArgsToMethodForwarder()
{
    makeArgsToMethodForwarder_impl
    makeArgsToMethodForwarder_impl const
}

##########################################################
# here we go...
makeLists
false && {
    echo funcSig=${funcSig}
    echo tmplsig=${tmplsig}
    echo tmplsigV=${tmplsigV}
    echo tmplspecV=${tmplspecV}
}


for command in $@; do
case $command in
#    'MemFuncForwarder')
#	makeMemFuncForwarder
#	;;
#    'TMemFuncForwarder')
#	makeTMemFuncForwarder
#	;;
#    'FunctorForwarder')
#	makeFunctorForwarder
#	;;
#    'FunctionForwarder')
#        makeFunctionForwarder
#        ;;
#    'CtorForwarder')
#	makeCtorForwarder
#	;;
    *Signature|SignatureBase|FunctionToInCa|MethodToInCa|ArgsTo*Forwarder|CtorForwarder)
	make${command}
	;;
    *)
	echo "Unhandled command: ${command}"
	exit 2
    ;;
esac
done
