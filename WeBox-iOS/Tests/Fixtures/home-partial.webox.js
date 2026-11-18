WeBox.define({
    api: '1.5',
    id: 'test.home.partial',
    name: '目录测试',
    version: '1.0.0',
    filters: async () => [{
        key: 'kind',
        label: '分类',
        type: 'select',
        options: [{ value: 'failed', label: '不可用' }, { value: 'works', label: '可读' }]
    }],
    list: async (_, request) => {
        if (request.filters.kind === 'failed') throw new Error('分类不可用');
        return {
            items: [
                { id: '1', title: '可播放', kind: 'series' },
                { id: '1', title: '重复', kind: 'series' }
            ],
            nextCursor: null
        };
    },
    detail: async () => ({}),
    play: async () => ({ sources: [] })
});
