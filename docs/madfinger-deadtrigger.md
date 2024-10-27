# AI notes

## Enemy Config

+ anim set
+ max walk speed 1.1 .. 1.6
+ max run speed 2.5 .. 5.0
+ sensor type
+ {Action}
+ { Goal}

## Worldstate

+ Idling
+ AtTargetPos
+ TargetNode
+ InDodge
+ CoverState
+ SeeEnemy
+ KillTarget
+ LookingAtTarget
+ EnemyLookingAtMe
+ WeaponLoaded
+ WeaponChange
+ UseWorldObject
+ PlayAnim
+ InWeaponRange
+ InContestRange
+ InVomitRange
+ BodyPose
+ Event
+ AheadOfEnemy
+ EnemyAheadOfMe
+ Teleport
+ DoSpawnAction
+ Patrol
+ CriticalInjury
+ CheckBait
+ DestroyObject
+ Contest
+ Berserk
+ UseGadget: bool

## Goals

concepts:

+ on plan activation goal disabled for everyone for random period 0.5-2.5 sec
+

base:

+ owner
+ relevancy 0..1
+ fail chance
+ goal type
+ next evaluation time

types: (type, relevancy)

+ SpawnAction
+ Advance
+ FallBack
+ RunAway
+ KeepCombatRange
+ Move
+ LookAtTarget
+ CheckEvent
+ KillTarget
+ SuppressiveFire
+ WeaponReload
+ WeaponChange
+ Dodge
+ Alert
+ Calm
+ UseWorldObject
+ PlayAnim
+ CriticalInjury
+ IdleAnim
+ Teleport
+ Suppressed
+ CheckBait
+ DestroyObject
+ Contest
+ UseGadget

## Actions

+ Move
+ GoTo
+ GoToWeaponRange
+ CheckBait
+ DestroyObject
+ Contest
+ Fallback
+ LookAtTarget
+ CheckEvent
+ CheckLostEnemy
+ WeaponReload
+ WeaponChange
+ Use
+ PlayAnim
+ AttackMelee
+ AttackVomit
+ Knockdown
+ Teleport
+ DodgeStrafe
+ DodgeStrafeWalk
+ Patrol
+ ShielderGoto
+ CritInjury
+ Suppressed
+ UseGadget
