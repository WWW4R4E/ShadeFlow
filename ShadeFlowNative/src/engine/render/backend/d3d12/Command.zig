const std = @import("std");

const win32 = @import("win32").everything;
// void CreateCommandComponents()
// 	{
// 		// 队列信息结构体，这里只需要填队列的类型 type 就行了
// 		D3D12_COMMAND_QUEUE_DESC queueDesc = {};
// 		// D3D12_COMMAND_LIST_TYPE_DIRECT 表示将命令都直接放进队列里，不做其他处理
// 		queueDesc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
// 		// 创建命令队列
// 		m_D3D12Device->CreateCommandQueue(&queueDesc, IID_PPV_ARGS(&m_CommandQueue));
//
// 		// 创建命令分配器，它的作用是开辟内存，存储命令列表上的命令，注意命令类型要一致
// 		m_D3D12Device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&m_CommandAllocator));
//
// 		// 创建图形命令列表，注意命令类型要一致
// 		m_D3D12Device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, m_CommandAllocator.Get(),
// 			nullptr, IID_PPV_ARGS(&m_CommandList));
//
// 		// 命令列表创建时处于 Record 录制状态，我们需要关闭它，这样下文的 Reset 才能成功
// 		m_CommandList->Close();
// 	}
pub const Command = struct {
    command_queue_desc: *win32.D3D12_COMMAND_QUEUE_DESC,
};
