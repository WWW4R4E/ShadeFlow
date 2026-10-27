using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using Windows.Storage.Pickers;
using Windows.System;

namespace ShadeFlow
{
  public sealed partial class MainWindow : Window
  {

    public MainWindow()
    {
            ExtendsContentIntoTitleBar = true;
            AppWindow.TitleBar.PreferredHeightOption = Microsoft.UI.Windowing.TitleBarHeightOption.Tall;
            InitializeComponent();
    }

    private async void Open_Click(object sender, RoutedEventArgs e)
    {
      var picker = new FolderPicker();
      picker.CommitButtonText = "选择文件夹";
      picker.SuggestedStartLocation = PickerLocationId.DocumentsLibrary;
      picker.ViewMode = PickerViewMode.List;

      var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
      WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);

      var folder = await picker.PickSingleFolderAsync();
      if (folder != null)
      {
          Debug.WriteLine("已选择: " + folder.Path);
          
          if (Content is Grid rootGrid && rootGrid.Children.Count > 1)
          {
              var homePage = rootGrid.Children[1] as Views.HomePage;
              if (homePage != null)
              {
                  homePage.SelectedFolderPath = folder.Path;
              }
          }
      }
    }

    private void NewWindow_Click(object sender, RoutedEventArgs e)
    {
    }

    // 保存场景：FileSavePicker 选路径 → 场景树导出 JSON
    private async void SaveScene_Click(object sender, RoutedEventArgs e)
    {
      if (Views.Controls.SceneTreeControl.Instance == null) return;

      var picker = new FileSavePicker();
      picker.SuggestedStartLocation = PickerLocationId.DocumentsLibrary;
      picker.SuggestedFileName = "scene";
      picker.FileTypeChoices.Add("ShadeFlow 场景", new List<string> { ".json" });

      var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
      WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);

      var file = await picker.PickSaveFileAsync();
      if (file == null) return;

      if (!Views.Controls.SceneTreeControl.Instance.SaveScene(file.Path))
      {
        var dialog = new ContentDialog
        {
          Title = "保存场景",
          Content = "保存失败，详见引擎日志（Debug 输出）。",
          CloseButtonText = "确定",
          XamlRoot = Content.XamlRoot
        };
        _ = dialog.ShowAsync();
      }
    }

    // 加载场景：FileOpenPicker 选 JSON → 清空当前场景重建
    private async void LoadScene_Click(object sender, RoutedEventArgs e)
    {
      if (Views.Controls.SceneTreeControl.Instance == null) return;

      var picker = new FileOpenPicker();
      picker.SuggestedStartLocation = PickerLocationId.DocumentsLibrary;
      picker.FileTypeFilter.Add(".json");

      var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
      WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);

      var file = await picker.PickSingleFileAsync();
      if (file == null) return;

      if (!Views.Controls.SceneTreeControl.Instance.LoadScene(file.Path))
      {
        var dialog = new ContentDialog
        {
          Title = "加载场景",
          Content = "加载失败：文件格式不正确或磁盘读取出错，详见引擎日志（Debug 输出）。",
          CloseButtonText = "确定",
          XamlRoot = Content.XamlRoot
        };
        _ = dialog.ShowAsync();
      }
    }

    private void Exit_Click(object sender, RoutedEventArgs e)
    {
      this.Close();
    }

    private void MainSidebar_Click(object sender, RoutedEventArgs e)
    {
      // TODO 实现主侧边栏显示/隐藏的逻辑
    }

    private void SecondarySidebar_Click(object sender, RoutedEventArgs e)
    {
      // TODO 实现辅助侧边栏显示/隐藏的逻辑
    }

    private void StatusBar_Click(object sender, RoutedEventArgs e)
    {
      // TODO 实现状态栏显示/隐藏的逻辑
    }

    private async void About_Click(object sender, RoutedEventArgs e)
    {
      var uri = new Uri("https://github.com/WWW4R4E/ShadeFlow/");
      await Launcher.LaunchUriAsync(uri);
    }

    private async void Feedback_Click(object sender, RoutedEventArgs e)
    {
      var uri = new Uri("https://github.com/WWW4R4E/ShadeFlow/issues");
      await Launcher.LaunchUriAsync(uri);
    }

  }
}