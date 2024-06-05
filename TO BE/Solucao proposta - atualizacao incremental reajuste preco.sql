
CREATE PROCEDURE [P_Atualizar_Tabela_Materializada_Reajuste_Preco] AS


-- Seleciona apenas os dados que não estão na tabela destino
SELECT *
INTO #reajuste_preco
FROM [vw_reajuste_preco] t_view

WHERE NOT EXISTS (
	SELECT 1 FROM VBA_v_reajustePreco_ t_mat
	WHERE t_view.ID_Reajuste_preco = t_mat.ID_Reajuste_preco
)

--Seleciona registro que possuem vigência aberta na tabela destino, que possuem versão mais recente do dado e que precisam ter vigÊncia fechada.
SELECT DISTINCT
t_mat.ID_Reajuste_preco
INTO #TEMP_REGISTROS_MODIFICADOS
FROM dbo.vw_reajustePreco_mat AS t_mat

-- Join nos dados de vigencia aberta com o mesmo ID_PERSIST 
INNER JOIN #reajuste_preco AS t_view

ON t_mat.ID_Contratos_196_Persist = t_view.ID_Contratos_196_Persist 
AND t_view.Cenario = t_mat.Cenario
AND t_view.DT_Fim_Vig = '9999-12-31'
AND t_mat.DT_Fim_Vig = '9999-12-31'

-- Retorna apenas os dados que tenham modificações (diferentes IDs únicos)
WHERE t_view.ID_Reajuste_preco <> t_mat.ID_Reajuste_preco


-- Encerra a vigência dos dados que tenham versão mais recente

UPDATE t_mat

SET t_mat.DT_Fim_Vig = origem.Dt_Fim_Vig
FROM dbo.vw_reajustePreco_mat AS t_mat

-- Join nos dados que foram modificados
INNER JOIN #TEMP_REGISTROS_MODIFICADOS AS t_view

ON t_view.ID_Reajuste_preco = t_mat.ID_Reajuste_preco
--join nos dados na fonte primária dos dados para pegar a data fim vigencia mais confiável
INNER JOIN Fato_Reajuste_Preco_Atual origem

ON origem.ID_Reajuste_preco = ROUND((t_mat.ID_Reajuste_preco) / 10, 0)



--Seleciona dados da view vw_reajuste_preco que estão com a vigência fechada e que tiveram dt_fim_vig
-- nos últimos 15 dias
SELECT 
A.ID_Reajuste_preco,
A.DT_Fim_Vig
INTO #TEMP_PPA_PORTAL
FROM [vw_reajuste_preco] A
WHERE DT_Fim_Vig > CONVERT(DATE, GETDATE() -15)
AND DT_Fim_Vig <> '9999-12-31'


CREATE CLUSTERED INDEX IC_ID_VBA_CONTRATOS_196
ON #TEMP_PPA_PORTAL (ID_Reajuste_preco) 

--Altera a data de vigência da tabela materializada de reajuste de preço que foram encerrados na VBA contratos e não receberam nova vigência. 
UPDATE A
SET DT_Fim_Vig = B.DT_Fim_Vig
FROM dbo.vw_reajustePreco_mat A
INNER JOIN #TEMP_PPA_PORTAL B
ON A.ID_Reajuste_preco = B.ID_Reajuste_preco
WHERE A.DT_Fim_Vig <> B.DT_Fim_Vig


-- Insere os dados cujo ID único não estão na tabela materializada
INSERT INTO vw_reajustePreco_mat 

SELECT *
FROM #reajuste_preco



DROP TABLE #reajuste_preco;

