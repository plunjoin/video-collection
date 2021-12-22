-- 1. 事务开始
BEGIN;

-- 2. 针对 76 部出现重复节点的视频进行精准剔除：
-- 若同一个视频中，存在一个既有 source_id 又具有相同 player_code 的新线路，
-- 则移除历史残留的无 source_id 旧线路。
UPDATE videos
SET play_groups = (
    SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb)
    FROM jsonb_array_elements(play_groups) elem
    WHERE NOT (
        COALESCE(elem->>'source_id', '') = '' 
        AND EXISTS (
            SELECT 1 FROM jsonb_array_elements(play_groups) e2 
            WHERE COALESCE(e2->>'source_id', '') != '' 
            AND e2->>'player_code' = elem->>'player_code'
        )
    )
)
WHERE jsonb_array_length(play_groups) > 1
AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(play_groups) elem
    WHERE COALESCE(elem->>'source_id', '') = '' 
    AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(play_groups) e2 
        WHERE COALESCE(e2->>'source_id', '') != '' 
        AND e2->>'player_code' = elem->>'player_code'
    )
);

-- 3. 针对所有尚未填充 source_id 的历史线路（全库约 14.6 万条），标准化填补量子资源站节点信息
UPDATE videos
SET play_groups = (
    SELECT COALESCE(jsonb_agg(
        CASE 
            WHEN COALESCE(elem->>'source_id', '') = '' THEN
                jsonb_set(
                    jsonb_set(
                        jsonb_set(
                            jsonb_set(elem, '{source_id}', '"liangzi_zy"'::jsonb),
                            '{source_name}', '"量子资源站"'::jsonb
                        ),
                        '{server}', '"量子资源站"'::jsonb
                    ),
                    '{from}', to_jsonb('量子资源站 (' || COALESCE(elem->>'player_code', 'm3u8') || ')')
                )
            ELSE elem
        END
    ), '[]'::jsonb)
    FROM jsonb_array_elements(play_groups) elem
)
WHERE EXISTS (
    SELECT 1 FROM jsonb_array_elements(play_groups) elem
    WHERE COALESCE(elem->>'source_id', '') = ''
);

-- 4. 提交事务
COMMIT;
