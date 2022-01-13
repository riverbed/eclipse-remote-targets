//
// Copyright (c) 2022 Riverbed Technology LLC
//
// This software is licensed under the terms and conditions of the MIT License
// accompanying the software ("License").  This software is distributed "AS IS"
// as set forth in the License.
//

#define __STR2__(x) #x

#define __STR1__(x) __STR2__(x)

#define __PPOUT__(x) "#define " #x " " __STR1__(x)

#if defined(_ATL_VER)
    #pragma message(__PPOUT__(_ATL_VER               ))
#endif

#if defined(_CHAR_UNSIGNED         )
    #pragma message(__PPOUT__(_CHAR_UNSIGNED         ))
#endif

#if defined(__CLR_VER              )
    #pragma message(__PPOUT__(__CLR_VER              ))
#endif

#if defined(__cplusplus_cli        )
    #pragma message(__PPOUT__(__cplusplus_cli        ))
#endif

#if defined(__COUNTER__            )
    #pragma message(__PPOUT__(__COUNTER__            ))
#endif

#if defined(__cplusplus            )
    #pragma message(__PPOUT__(__cplusplus            ))
#endif

#if defined(_CPPLIB_VER            )
    #pragma message(__PPOUT__(_CPPLIB_VER            ))
#endif

#if defined(_CPPRTTI               )
    #pragma message(__PPOUT__(_CPPRTTI               ))
#endif

#if defined(_CPPUNWIND             )
    #pragma message(__PPOUT__(_CPPUNWIND             ))
#endif

// #pragma message("#define _CRTIMP")

#if defined(_DEBUG                 )
    #pragma message(__PPOUT__(_DEBUG                 ))
#endif

#if defined(_DLL                   )
    #pragma message(__PPOUT__(_DLL                   ))
#endif

//#if defined(__FUNCDNAME__          )
//    #pragma message(__PPOUT__(__FUNCDNAME__          ))
//#endif
#pragma message("#define __FUNCDNAME__ __func__")

//#if defined(__FUNCSIG__            )
//    #pragma message(__PPOUT__(__FUNCSIG__            ))
//#endif
#pragma message("#define __FUNCSIG__ __func__")

//#if defined(__FUNCTION__           )
//    #pragma message(__PPOUT__(__FUNCTION__           ))
//#endif
#pragma message("#define __FUNCTION__ __func__")

#pragma message("#define __cdecl")
#pragma message("#define __fastcall")
#pragma message("#define __forceinline __inline")
#pragma message("#define __restrict")
#pragma message("#define __sptr")
#pragma message("#define __stdcall")
#pragma message("#define __unaligned")
#pragma message("#define __uptr")
#pragma message("#define __w64")

#pragma message("#define __int8 char")
#pragma message("#define __int16 short")
#pragma message("#define __int32 int")
#pragma message("#define __int64 long long")

#if defined(_INTEGRAL_MAX_BITS     )
    #pragma message(__PPOUT__(_INTEGRAL_MAX_BITS     ))
#endif

#if defined(_M_ALPHA               )
    #pragma message(__PPOUT__(_M_ALPHA               ))
#endif

#if defined(_M_CEE                 )
    #pragma message(__PPOUT__(_M_CEE                 ))
#endif

#if defined(_M_CEE_PURE            )
    #pragma message(__PPOUT__(_M_CEE_PURE            ))
#endif

#if defined(_M_CEE_SAFE            )
    #pragma message(__PPOUT__(_M_CEE_SAFE            ))
#endif

#if defined(_M_IX86                )
    #pragma message(__PPOUT__(_M_IX86                ))
#endif

#if defined(_M_IA64                )
    #pragma message(__PPOUT__(_M_IA64                ))
#endif

#if defined(_M_IX86_FP             )
    #pragma message(__PPOUT__(_M_IX86_FP             ))
#endif

#if defined(_M_MPPC                )
    #pragma message(__PPOUT__(_M_MPPC                ))
#endif

#if defined(_M_MRX000              )
    #pragma message(__PPOUT__(_M_MRX000              ))
#endif

#if defined(_M_PPC                 )
    #pragma message(__PPOUT__(_M_PPC                 ))
#endif

#if defined(_M_X64                 )
    #pragma message(__PPOUT__(_M_X64                 ))
#endif

#if defined(_MANAGED               )
    #pragma message(__PPOUT__(_MANAGED               ))
#endif

#if defined(_MFC_VER               )
    #pragma message(__PPOUT__(_MFC_VER               ))
#endif

#if defined(_MSC_BUILD             )
    #pragma message(__PPOUT__(_MSC_BUILD             ))
#endif

#if defined(_MSC_EXTENSIONS        )
    #pragma message(__PPOUT__(_MSC_EXTENSIONS        ))
#endif

#if defined(_MSC_FULL_VER          )
    #pragma message(__PPOUT__(_MSC_FULL_VER          ))
#endif

#if defined(_MSC_VER               )
    #pragma message(__PPOUT__(_MSC_VER               ))
#endif

#if defined(__MSVC_RUNTIME_CHECKS  )
    #pragma message(__PPOUT__(__MSVC_RUNTIME_CHECKS  ))
#endif

#if defined(_MT                    )
    #pragma message(__PPOUT__(_MT                    ))
#endif

#if defined(_NATIVE_WCHAR_T_DEFINED)
    #pragma message(__PPOUT__(_NATIVE_WCHAR_T_DEFINED))
#endif

#if defined(_OPENMP                )
    #pragma message(__PPOUT__(_OPENMP                ))
#endif

#if defined(_VC_NODEFAULTLIB       )
    #pragma message(__PPOUT__(_VC_NODEFAULTLIB       ))
#endif

#if defined(_WCHAR_T_DEFINED       )
    #pragma message(__PPOUT__(_WCHAR_T_DEFINED       ))
#endif

#if defined(_WIN32                 )
    #pragma message(__PPOUT__(_WIN32                 ))
#endif

#if defined(_WIN64                 )
    #pragma message(__PPOUT__(_WIN64                 ))
#endif

#if defined(_Wp64                  )
    #pragma message(__PPOUT__(_Wp64                  ))
#endif

void main()
{
    // DO NOTHING
}
