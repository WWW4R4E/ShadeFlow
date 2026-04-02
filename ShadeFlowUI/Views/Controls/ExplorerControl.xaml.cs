using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using ShadeFlow.Models;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using Windows.ApplicationModel.DataTransfer;

namespace ShadeFlow.Views.Controls
{
    public sealed partial class ExplorerControl : UserControl
    {
        private ObservableCollection<TreeViewItemModel> _treeViewItems;
        private TreeViewItemModel _clipboardItem;
        private string _originalFolderPath;

        public ExplorerControl()
        {
            this.InitializeComponent();
            FileTreeView.DragItemsStarting += FileTreeView_DragItemsStarting;
            FileTreeView.DragItemsCompleted += FileTreeView_DragItemsCompleted;
        }

        // 加载指定路径的文件夹
        public void LoadFolder(string folderPath)
        {
            _originalFolderPath = folderPath;
            _treeViewItems = new ObservableCollection<TreeViewItemModel>();

            var rootFolder = new TreeViewItemModel
            {
                Name = Path.GetFileName(folderPath),
                IsExpanded = true
            };

            LoadFolderContents(rootFolder, folderPath);

            _treeViewItems.Add(rootFolder);
            FileTreeView.ItemsSource = _treeViewItems;
        }

        // 递归加载文件夹内容
        private void LoadFolderContents(TreeViewItemModel parent, string folderPath)
        {
            foreach (var subFolderPath in Directory.GetDirectories(folderPath))
            {
                var folderName = Path.GetFileName(subFolderPath);
                var folderItem = new TreeViewItemModel
                {
                    Name = folderName,
                    IsExpanded = false,
                    Icon = "\uE8B7" 
                };
                parent.Children.Add(folderItem);
                LoadFolderContents(folderItem, subFolderPath);
            }

            foreach (var filePath in Directory.GetFiles(folderPath))
            {
                var fileName = Path.GetFileName(filePath);
                var fileItem = new TreeViewItemModel
                {
                    Name = fileName,
                    Icon = "\uE7C3"
                };
                parent.Children.Add(fileItem);
            }
        }

        // 右键点击事件
        private void FileTreeView_RightTapped(object sender, Microsoft.UI.Xaml.Input.RightTappedRoutedEventArgs e)
        {
            var clickedItem = e.OriginalSource as FrameworkElement;
            if (clickedItem?.DataContext is TreeViewItemModel model)
            {
                FileTreeView.SelectedItem = model;
            }
        }

        // 拖动开始事件
        private void FileTreeView_DragItemsStarting(TreeView sender, TreeViewDragItemsStartingEventArgs e)
        {
            if (e.Items.Count > 0 && e.Items[0] is TreeViewItemModel itemToDrag)
            {
                e.Data.Properties["TreeViewItemModel"] = itemToDrag;
                e.Data.RequestedOperation = DataPackageOperation.Move;
            }
        }

        // 查找父级TreeViewItemModel
        private TreeViewItemModel FindAncestorTreeViewItemModel(FrameworkElement element)
        {
            if (element?.DataContext is TreeViewItemModel model)
            {
                return model;
            }

            var parent = element?.Parent as FrameworkElement;
            while (parent != null)
            {
                if (parent.DataContext is TreeViewItemModel itemModel)
                {
                    return itemModel;
                }
                parent = parent.Parent as FrameworkElement;
            }
            return null;
        }

        // 拖动完成事件 - 获取整个数据结构并同步到文件系统
        private void FileTreeView_DragItemsCompleted(TreeView sender, TreeViewDragItemsCompletedEventArgs e)
        {
            SynchronizeTreeToFileSystem(_treeViewItems);
        }

        // 检查 item 是否是 parent 的后代节点
        private bool IsDescendantOf(TreeViewItemModel item, TreeViewItemModel parent)
        {
            var current = parent;
            while (current != null)
            {
                if (current == item)
                {
                    return true;
                }
                foreach (var child in current.Children)
                {
                    if (child == item || IsDescendantOf(item, child))
                    {
                        return true;
                    }
                }
                break;
            }
            return false;
        }


        // 遍历树形结构并同步到文件系统
        private void SynchronizeTreeToFileSystem(IEnumerable<TreeViewItemModel> items)
        {
            foreach (var item in items)
            {
                var expectedPath = GetFullPath(item);
                if (IsFile(item))
                {
                    var actualPath = FindActualPathOfFile(item);
                    File.Move(actualPath, expectedPath);

                }
                else
                {
                    var actualPath = FindActualPathOfFolder(item);
                    Directory.Move(actualPath, expectedPath);
                }
                // 递归处理子项
                if (item.Children.Count > 0)
                {
                    SynchronizeTreeToFileSystem(item.Children);
                }
            }
        }

        // 查找文件的实际路径
        private string FindActualPathOfFile(TreeViewItemModel item)
        {
            // 搜索整个原始目录以查找文件的实际位置
            var searchPattern = item.Name;
            var files = Directory.GetFiles(_originalFolderPath, searchPattern, SearchOption.AllDirectories);

            if (files.Length > 0)
            {
                foreach (var filePath in files)
                {
                    System.Diagnostics.Debug.WriteLine($"找到文件: {filePath}");
                }
                return files[0];
            }

            System.Diagnostics.Debug.WriteLine($"未找到文件: {item.Name}");
            return string.Empty;
        }

        // 查找文件夹的实际路径
        private string FindActualPathOfFolder(TreeViewItemModel item)
        {
            var searchPattern = item.Name;
            var folders = Directory.GetDirectories(_originalFolderPath, searchPattern, SearchOption.AllDirectories);

            if (folders.Length > 0)
            {
                // 返回找到的第一个匹配项
                foreach (var folderPath in folders)
                {
                    System.Diagnostics.Debug.WriteLine($"找到文件夹: {folderPath}");
                }
                return folders[0]; 
            }

            System.Diagnostics.Debug.WriteLine($"未找到文件夹: {item.Name}");
            return string.Empty;
        }

        // 为 TreeViewItem 的键盘加速器添加事件处理方法
        private void TreeViewItem_DeleteAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
        {
            DeleteItem_Click(null, null);
            args.Handled = true;
        }

        private void TreeViewItem_RenameAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
        {
            RenameItem_Click(null, null);
            args.Handled = true;
        }

        private void TreeViewItem_OpenAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
        {
            OpenItem_Click(null, null);
            args.Handled = true;
        }

        private void TreeViewItem_CutAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
        {
            CutItem_Click(null, null);
            args.Handled = true;
        }

        private void TreeViewItem_CopyAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
        {
            CopyItem_Click(null, null);
            args.Handled = true;
        }

        private void TreeViewItem_PasteAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
        {
            PasteItem_Click(null, null);
            args.Handled = true;
        }


        // TODO: 使用vsc打开项目
        private void OpenItem_Click(object sender, RoutedEventArgs e)
        {
            if (FileTreeView.SelectedItem is TreeViewItemModel selectedItem)
            {
                var fullPath = GetFullPath(selectedItem);
                if (Directory.Exists(fullPath))
                {
                    selectedItem.IsExpanded = !selectedItem.IsExpanded;
                }
                else if (File.Exists(fullPath))
                {
                    // 尝试打开文件
                    try
                    {
                        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
                        {
                            FileName = fullPath,
                            UseShellExecute = true
                        });
                    }
                    catch
                    {
                        // 无法打开文件
                    }
                }
            }
        }

        // 剪切项目
        private void CutItem_Click(object sender, RoutedEventArgs e)
        {
            if (FileTreeView.SelectedItem is TreeViewItemModel selectedItem)
            {
                _clipboardItem = selectedItem;
            }
        }

        // 复制项目
        private void CopyItem_Click(object sender, RoutedEventArgs e)
        {
            if (FileTreeView.SelectedItem is TreeViewItemModel selectedItem)
            {
                _clipboardItem = selectedItem;
            }
        }

        // 粘贴项目
        private void PasteItem_Click(object sender, RoutedEventArgs e)
        {
            if (_clipboardItem == null) return;

            if (FileTreeView.SelectedItem is TreeViewItemModel targetDir)
            {
                if (IsFile(targetDir))
                {
                    targetDir = FindParentOfItem(targetDir);
                }

                if (targetDir != null)
                {
                    PerformPaste(_clipboardItem, targetDir);
                }
            }
            else if (sender == null)
            {
                if (_treeViewItems.Count > 0)
                {
                    PerformPaste(_clipboardItem, _treeViewItems[0]);
                }
            }
        }

        // 执行粘贴操作
        private void PerformPaste(TreeViewItemModel itemToPaste, TreeViewItemModel targetDir)
        {
            var sourcePath = GetFullPath(itemToPaste);
            var targetPath = GetFullPath(targetDir);

            if (string.IsNullOrEmpty(targetPath)) return;

            string destinationPath;

            if (Directory.Exists(sourcePath))
            {
                destinationPath = Path.Combine(targetPath, itemToPaste.Name);
                if (_clipboardItem == itemToPaste)
                {
                    try
                    {
                        Directory.Move(sourcePath, destinationPath);

                        RemoveItemFromTree(itemToPaste);
                        targetDir.Children.Add(itemToPaste);
                    }
                    catch (Exception ex)
                    {
                        ShowErrorDialog($"移动文件夹失败: {ex.Message}");
                    }
                }
                else
                {
                    CopyDirectory(sourcePath, destinationPath);

                    var newItem = new TreeViewItemModel
                    {
                        Name = itemToPaste.Name,
                        Icon = itemToPaste.Icon
                    };

                    CopyChildren(itemToPaste, newItem);

                    targetDir.Children.Add(newItem);
                }
            }
            else if (File.Exists(sourcePath))
            {
                destinationPath = Path.Combine(targetPath, itemToPaste.Name);

                if (_clipboardItem == itemToPaste)
                {
                    try
                    {
                        File.Move(sourcePath, destinationPath);
                        RemoveItemFromTree(itemToPaste);
                        targetDir.Children.Add(itemToPaste);
                    }
                    catch (Exception ex)
                    {
                        ShowErrorDialog($"移动文件失败: {ex.Message}");
                    }
                }
                else
                {
                    var fileNameWithoutExt = Path.GetFileNameWithoutExtension(itemToPaste.Name);
                    var extension = Path.GetExtension(itemToPaste.Name);
                    var counter = 1;
                    var finalDestinationPath = destinationPath;

                    while (File.Exists(finalDestinationPath))
                    {
                        finalDestinationPath = Path.Combine(targetPath, $"{fileNameWithoutExt} ({counter}){extension}");
                        counter++;
                    }

                    File.Copy(sourcePath, finalDestinationPath);

                    var newItem = new TreeViewItemModel
                    {
                        Name = Path.GetFileName(finalDestinationPath),
                        Icon = itemToPaste.Icon
                    };

                    targetDir.Children.Add(newItem);
                }
            }
        }

        // 复制子项的辅助方法
        private void CopyChildren(TreeViewItemModel sourceItem, TreeViewItemModel targetItem)
        {
            foreach (var child in sourceItem.Children)
            {
                var newChild = new TreeViewItemModel
                {
                    Name = child.Name,
                    Icon = child.Icon
                };

                if (child.Children.Count > 0)
                {
                    CopyChildren(child, newChild);
                }

                targetItem.Children.Add(newChild);
            }
        }

        // 获取项目完整路径
        private string GetFullPath(TreeViewItemModel item)
        {
            var path = FindPathInTree(_treeViewItems, item);
            if (!string.IsNullOrEmpty(path))
            {
                return path;
            }

            return Path.Combine(_originalFolderPath, item.Name);
        }

        // 在树中查找从根到指定项的路径
        private string FindPathInTree(IEnumerable<TreeViewItemModel> rootItems, TreeViewItemModel targetItem)
        {
            foreach (var item in rootItems)
            {
                var path = FindPathRecursive(item, targetItem, new List<string>());
                if (!string.IsNullOrEmpty(path))
                {
                    return path;
                }
            }
            return string.Empty;
        }

        // 递归查找路径
        private string FindPathRecursive(TreeViewItemModel currentItem, TreeViewItemModel targetItem, List<string> pathSoFar)
        {
            // 添加当前项到路径
            pathSoFar.Add(currentItem.Name);

            // 如果当前项就是要找的项，返回路径
            if (currentItem == targetItem)
            {
                var path = string.Join(Path.DirectorySeparatorChar.ToString(), pathSoFar);
                // 替换根目录名称为实际路径
                var parts = path.Split(Path.DirectorySeparatorChar);
                parts[0] = _originalFolderPath;
                return string.Join(Path.DirectorySeparatorChar.ToString(), parts);
            }

            // 检查子项
            foreach (var child in currentItem.Children)
            {
                var result = FindPathRecursive(child, targetItem, pathSoFar);
                if (!string.IsNullOrEmpty(result))
                {
                    return result;
                }
            }

            // 回溯
            pathSoFar.RemoveAt(pathSoFar.Count - 1);
            return string.Empty;
        }

        // 检查项目是否为文件
        private bool IsFile(TreeViewItemModel item)
        {
            // 如果没有子项且图标是文件图标，则认为是文件
            return item.Children.Count == 0 && item.Icon == "\uE7C3";
        }

        // 删除项目
        private void DeleteItem_Click(object sender, RoutedEventArgs e)
        {
            if (FileTreeView.SelectedItem is TreeViewItemModel selectedItem)
            {
                var fullPath = GetFullPath(selectedItem);

                var dialog = new ContentDialog()
                {
                    Title = "确认删除",
                    Content = $"您确定要删除 '{selectedItem.Name}' 吗？\n此操作不可逆！",
                    PrimaryButtonText = "确定",
                    CloseButtonText = "取消",
                    XamlRoot = this.XamlRoot
                };

                var result = dialog.ShowAsync();
                result.Completed = async (asyncInfo, asyncStatus) =>
                {
                    if (asyncInfo.GetResults() == ContentDialogResult.Primary)
                    {
                        try
                        {
                            if (Directory.Exists(fullPath))
                            {
                                Directory.Delete(fullPath, true);
                            }
                            else if (File.Exists(fullPath))
                            {
                                File.Delete(fullPath);
                            }

                            // 从UI中移除项目 - 找到并从其父级中移除
                            RemoveItemFromTree(selectedItem);
                        }
                        catch (Exception ex)
                        {
                            await ShowErrorDialogAsync($"删除失败: {ex.Message}");
                        }
                    }
                };
            }
        }

        // 从树中移除项目
        private void RemoveItemFromTree(TreeViewItemModel itemToRemove)
        {
            // 从根开始查找并移除项目
            foreach (var rootItem in _treeViewItems)
            {
                if (RemoveItemRecursive(rootItem, itemToRemove))
                    return;
            }
        }

        // 递归查找并移除项目
        private bool RemoveItemRecursive(TreeViewItemModel parent, TreeViewItemModel itemToRemove)
        {
            if (parent.Children.Contains(itemToRemove))
            {
                parent.Children.Remove(itemToRemove);
                return true;
            }

            foreach (var child in parent.Children)
            {
                if (RemoveItemRecursive(child, itemToRemove))
                    return true;
            }

            return false;
        }

        // 重命名项目
        private void RenameItem_Click(object sender, RoutedEventArgs e)
        {
            if (FileTreeView.SelectedItem is TreeViewItemModel selectedItem)
            {
                var textBox = new TextBox
                {
                    Text = selectedItem.Name,
                    Margin = new Thickness(0, 10, 0, 10)
                };

                var dialog = new ContentDialog()
                {
                    Title = "重命名",
                    Content = textBox,
                    PrimaryButtonText = "确定",
                    CloseButtonText = "取消",
                    XamlRoot = this.XamlRoot
                };

                var result = dialog.ShowAsync();
                result.Completed = (asyncInfo, asyncStatus) =>
                {
                    if (asyncInfo.GetResults() == ContentDialogResult.Primary)
                    {
                        var newName = textBox.Text.Trim();
                        if (!string.IsNullOrEmpty(newName) && newName != selectedItem.Name)
                        {
                            var currentPath = GetFullPath(selectedItem);
                            var parentPath = Path.GetDirectoryName(currentPath);
                            var newPath = Path.Combine(parentPath, newName);

                            try
                            {
                                if (Directory.Exists(currentPath))
                                {
                                    Directory.Move(currentPath, newPath);
                                }
                                else if (File.Exists(currentPath))
                                {
                                    File.Move(currentPath, newPath);
                                }
                                selectedItem.Name = newName;
                            }
                            catch (Exception ex)
                            {
                                _ = ShowErrorDialogAsync($"重命名失败: {ex.Message}");
                            }
                        }
                    }
                };
            }
        }

        // 新建文件夹
        private void NewFolderItem_Click(object sender, RoutedEventArgs e)
        {
            if (FileTreeView.SelectedItem is TreeViewItemModel selectedItem)
            {
                if (IsFile(selectedItem))
                {
                    selectedItem = FindParentOfItem(selectedItem) ?? _treeViewItems[0];
                }

                CreateNewFolder(selectedItem ?? _treeViewItems[0]);
            }
            else if (_treeViewItems.Count > 0)
            {
                CreateNewFolder(_treeViewItems[0]);
            }
        }

        // 查找指定项的父项
        private TreeViewItemModel FindParentOfItem(TreeViewItemModel item)
        {
            foreach (var rootItem in _treeViewItems)
            {
                var parent = FindParentRecursive(rootItem, item);
                if (parent != null)
                    return parent;
            }
            return null;
        }

        // 递归查找父项
        private TreeViewItemModel FindParentRecursive(TreeViewItemModel current, TreeViewItemModel target)
        {
            foreach (var child in current.Children)
            {
                if (child == target)
                    return current;

                var result = FindParentRecursive(child, target);
                if (result != null)
                    return result;
            }
            return null;
        }

        // 创建新文件夹
        private void CreateNewFolder(TreeViewItemModel parentItem)
        {
            var counter = 1;
            var folderName = "新建文件夹";
            var fullPath = GetFullPath(parentItem);

            // 确保文件夹名唯一
            var newFolderName = folderName;
            var newFolderPath = Path.Combine(fullPath, newFolderName);
            while (Directory.Exists(newFolderPath))
            {
                newFolderName = $"{folderName} ({counter})";
                newFolderPath = Path.Combine(fullPath, newFolderName);
                counter++;
            }

            try
            {
                Directory.CreateDirectory(newFolderPath);

                var newFolder = new TreeViewItemModel
                {
                    Name = newFolderName,
                    Icon = "\uE8B7" 
                };

                parentItem.Children.Add(newFolder);
                FileTreeView.SelectedItem = newFolder;
            }
            catch (Exception ex)
            {
                _ = ShowErrorDialogAsync($"创建文件夹失败: {ex.Message}");
            }
        }

        // 新建文件
        private void NewItem_Click(object sender, RoutedEventArgs e)
        {
            // 这里可以扩展实现创建新文件的功能
        }

        // 复制目录
        private void CopyDirectory(string sourceDir, string destinationDir)
        {
            var dir = new DirectoryInfo(sourceDir);

            if (!dir.Exists)
                throw new DirectoryNotFoundException($"Source directory not found: {sourceDir}");

            var dirs = dir.GetDirectories();

            Directory.CreateDirectory(destinationDir);

            foreach (var file in dir.GetFiles())
            {
                var targetFilePath = Path.Combine(destinationDir, file.Name);
                file.CopyTo(targetFilePath);
            }

            foreach (var subDir in dirs)
            {
                var newDestinationDir = Path.Combine(destinationDir, subDir.Name);
                CopyDirectory(subDir.FullName, newDestinationDir);
            }
        }

        // 显示错误对话框
        private async System.Threading.Tasks.Task ShowErrorDialogAsync(string message)
        {
            var dialog = new ContentDialog()
            {
                Title = "错误",
                Content = message,
                CloseButtonText = "确定",
                XamlRoot = this.XamlRoot
            };
            await dialog.ShowAsync();
        }

        // 显示错误对话框（同步）
        private void ShowErrorDialog(string message)
        {
            var dialog = new ContentDialog()
            {
                Title = "错误",
                Content = message,
                CloseButtonText = "确定",
                XamlRoot = this.XamlRoot
            };
            _ = dialog.ShowAsync();
        }
    }
}