      SUBROUTINE UMAT(STRESS,STATEV,DDSDDE,SSE,SPD,SCD,
     1 RPL,DDSDDT,DRPLDE,DRPLDT,STRAN,DSTRAN,
     2 TIME,DTIME,TEMP,DTEMP,PREDEF,DPRED,MATERL,NDI,NSHR,NTENS,
     3 NSTATV,PROPS,NPROPS,COORDS,DROT,PNEWDT,CELENT,
     4 DFGRD0,DFGRD1,NOEL,NPT,KSLAY,KSPT,KSTEP,KINC)
C
      INCLUDE 'ABA_PARAM.INC'
C     IMPLICIT NONE
C
      CHARACTER*80 MATERL
      DIMENSION STRESS(NTENS),STATEV(NSTATV),
     1 DDSDDE(NTENS,NTENS),DDSDDT(NTENS),DRPLDE(NTENS),
     2 STRAN(NTENS),DSTRAN(NTENS),TIME(2),PREDEF(1),DPRED(1),
     3 PROPS(NPROPS),COORDS(3),DROT(3,3),
     4 DFGRD0(3,3),DFGRD1(3,3), STRALPHA(NTENS), STRCALC(NTENS),
     5 DSTRALPHA(NTENS), DSTRESS(NTENS), DSETEMP(NTENS,NTENS)
C
C     LOCAL ARRAYS
C     ----------------------------------------------------------------
C     EELAS - ELASTIC STRAINS
C     EPLAS - PLASTIC STRAINS
C     ALPHA - SHIFT TENSOR
C     FLOW - PLASTIC FLOW DIRECTIONS
C     OLDS - STRESS AT START OF INCREMENT
C     OLDPL - PLASTIC STRAINS AT START OF INCREMENT
C
      DIMENSION EELAS(6), EPLAS(6), ALPHA(6), FLOW(6), OLDS(6), OLDPL(6)
C
      PARAMETER(ZERO=0.D0, ONE=1.D0, TWO=2.D0, THREE=3.D0, SIX=6.D0,
     1 ENUMAX=.4999D0, TOLER=1.0D-6)
      REAL*8 XL,GC,PHI,PSIT,DAMAGE,PSI,H
C
C     ----------------------------------------------------------------
C     UMAT FOR ISOTROPIC ELASTICITY AND MISES PLASTICITY
C     WITH KINEMATIC HARDENING - CANNOT BE USED FOR PLANE STRESS
C     ----------------------------------------------------------------
C     PROPS(1) - E
C     PROPS(2) - NU
C     PROPS(3) - SYIELD
C     PROPS(4) - HARD
C ----------------------------------------------------------------
C
C     ELASTIC PROPERTIES
C
      EMOD=PROPS(1)
      ENU=MIN(PROPS(2), ENUMAX)
      EBULK3=EMOD/(ONE-TWO*ENU)
      EG2=EMOD/(ONE+ENU)
      EG=EG2/TWO
      EG3=THREE*EG
      ELAM=(EBULK3-EG2)/THREE
C
C     ELASTIC STIFFNESS
C
      DO K1=1, NDI
        DO K2=1, NDI
          DDSDDE(K2, K1)=ELAM
        END DO
        DDSDDE(K1, K1)=EG2+ELAM
      END DO
      DO K1=NDI+1, NTENS
        DDSDDE(K1, K1)=EG
      END DO  
C
C     RECOVER ELASTIC STRAIN, PLASTIC STRAIN AND SHIFT TENSOR AND ROTATE
C     NOTE: USE CODE 1 FOR (TENSOR) STRESS, CODE 2 FOR (ENGINEERING) STRAIN
C
      CALL ROTSIG(STATEV( 1), DROT, EELAS, 2, NDI, NSHR)
      CALL ROTSIG(STATEV( NTENS+1), DROT, EPLAS, 2, NDI, NSHR)
      CALL ROTSIG(STATEV(2*NTENS+1), DROT, ALPHA, 1, NDI, NSHR)
C
C     SAVE STRESS AND PLASTIC STRAINS AND
C     CALCULATE PREDICTOR STRESS AND ELASTIC STRAIN
C
      DO K1=1, NTENS
        OLDS(K1)=STRESS(K1)
        OLDPL(K1)=EPLAS(K1)
        EELAS(K1)=EELAS(K1)+DSTRAN(K1)
        DO K2=1, NTENS
          STRESS(K2)=STRESS(K2)+DDSDDE(K2, K1)*DSTRAN(K1)
        END DO
      END DO
C
C     CALCULATE EQUIVALENT VON MISES STRESS
C
      SMISES=(STRESS(1)-ALPHA(1)-STRESS(2)+ALPHA(2))**2
     1 +(STRESS(2)-ALPHA(2)-STRESS(3)+ALPHA(3))**2
     2 +(STRESS(3)-ALPHA(3)-STRESS(1)+ALPHA(1))**2
      DO K1=NDI+1,NTENS
        SMISES=SMISES+SIX*(STRESS(K1)-ALPHA(K1))**2
      END DO
      SMISES=SQRT(SMISES/TWO)
C
C     GET YIELD STRESS AND HARDENING MODULUS
C
      SYIELD=PROPS(3)
      HARD=PROPS(4)
C 
C     PHASE FIELD LENGTH SCALE
C 
      XL=PROPS(5)
C 
C     FRACTURE TOUGHNESS
C 
      GC=PROPS(6)
C 
C     FRACTURE PHASE FIELD VARIABLE
C 
      PHI=MAX(TEMP+DTEMP,STATEV(31))
      PSIT=STATEV(32)
C 
C     DEGRADATION FUNCTION
C 
      DAMAGE=(1.D0-PHI)**2+1.D-07
C
C     DETERMINE IF ACTIVELY YIELDING
C
      IF(SMISES.GT.(ONE+TOLER)*SYIELD) THEN
C
C     ACTIVELY YIELDING
C     SEPARATE THE HYDROSTATIC FROM THE DEVIATORIC STRESS
C     CALCULATE THE FLOW DIRECTION
C
      SHYDRO=(STRESS(1)+STRESS(2)+STRESS(3))/THREE
      DO K1=1,NDI
        FLOW(K1)=(STRESS(K1)-ALPHA(K1)-SHYDRO)/SMISES
      END DO
      DO K1=NDI+1,NTENS
        FLOW(K1)=(STRESS(K1)-ALPHA(K1))/SMISES
      END DO
C
C     SOLVE FOR EQUIVALENT PLASTIC STRAIN INCREMENT
C
      DEQPL=(SMISES-SYIELD)/(EG3+HARD)
C
C     UPDATE SHIFT TENSOR, ELASTIC AND PLASTIC STRAINS AND STRESS
C
      DO K1=1,NDI
        ALPHA(K1)=ALPHA(K1)+HARD*FLOW(K1)*DEQPL
        EPLAS(K1)=EPLAS(K1)+THREE/TWO*FLOW(K1)*DEQPL
        EELAS(K1)=EELAS(K1)-THREE/TWO*FLOW(K1)*DEQPL
        STRESS(K1)=ALPHA(K1)+FLOW(K1)*SYIELD+SHYDRO
      END DO
      DO K1=NDI+1,NTENS
        ALPHA(K1)=ALPHA(K1)+HARD*FLOW(K1)*DEQPL
        EPLAS(K1)=EPLAS(K1)+THREE*FLOW(K1)*DEQPL
        EELAS(K1)=EELAS(K1)-THREE*FLOW(K1)*DEQPL
        STRESS(K1)=ALPHA(K1)+FLOW(K1)*SYIELD
      END DO
C
C     CALCULATE PLASTIC DISSIPATION
C
      SPD=ZERO
      DO K1=1,NTENS
        SPD=SPD+(STRESS(K1)+OLDS(K1))*(EPLAS(K1)-OLDPL(K1))/TWO
      END DO
C
C     FORMULATE THE JACOBIAN (MATERIAL TANGENT)
C     FIRST CALCULATE EFFECTIVE MODULI
C
      EFFG=EG*(SYIELD+HARD*DEQPL)/SMISES
      EFFG2=TWO*EFFG
      EFFG3=THREE*EFFG
      EFFLAM=(EBULK3-EFFG2)/THREE
      EFFHRD=EG3*HARD/(EG3+HARD)-EFFG3
      DO K1=1, NDI
        DO K2=1, NDI
          DDSDDE(K2, K1)=EFFLAM
        END DO
        DDSDDE(K1, K1)=EFFG2+EFFLAM
      END DO
      DO K1=NDI+1, NTENS
        DDSDDE(K1, K1)=EFFG
      END DO
      DO K1=1, NTENS
        DO K2=1, NTENS
          DDSDDE(K2, K1)=DDSDDE(K2, K1)+EFFHRD*FLOW(K2)*FLOW(K1)
        END DO
      END DO
      ENDIF
C
C     STORE ELASTIC STRAINS, PLASTIC STRAINS AND SHIFT TENSOR
C     IN STATE VARIABLE ARRAY
C
      DO K1=1,NTENS
        STATEV(K1)=EELAS(K1)
        STATEV(K1+NTENS)=EPLAS(K1)
        STATEV(K1+2*NTENS)=ALPHA(K1)
      END DO
C
C     COMPUTE THE STRAIN ENERGY DENSITY
C
      PSI=0.D0
      DO I=1,NTENS
        PSI=PSI+STRESS(I)*STRAN(I)*0.5D0
      END DO
      H=MAX(PSIT,PSI)

      STRESS=STRESS*DAMAGE
      DDSDDE=DDSDDE*DAMAGE

      STATEV(31)=PHI
      STATEV(32)=H
      
      RPL=-(PHI/XL**2-2.D0*(1.D0-PHI)*H/(GC*XL))
      DRPLDT=-(1.D0/XL**2+2.D0*H/(GC*XL))

      RETURN
      END