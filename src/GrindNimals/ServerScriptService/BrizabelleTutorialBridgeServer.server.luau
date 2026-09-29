--============================================================
-- BRIZABELLE TUTORIAL BRIDGE - SAFE STUB
--
-- IMPORTANTE:
-- El bridge V1 anterior intentaba LEER RemoteFunction.OnServerInvoke.
-- Roblox no permite leer ese callback; solo asignarlo.
-- Por eso producia:
-- "OnServerInvoke is a callback member ... get is not available"
--
-- Esta version NO intercepta RemoteFunctions y por tanto NO genera el error.
-- La logica del huevo gratis debe vivir dentro de BrizabelleEggServer.
--============================================================

print("[BrizabelleTutorialBridge] SAFE | sin interceptar OnServerInvoke")
