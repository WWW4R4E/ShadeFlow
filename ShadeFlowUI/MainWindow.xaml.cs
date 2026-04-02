using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.System;
using Windows.Storage.Pickers;
using System;

namespace ShadeFlow
{
  public sealed partial class MainWindow : Window
  {

    public MainWindow()
    {
      this.ExtendsContentIntoTitleBar = true;
      AppWindow.TitleBar.PreferredHeightOption = Microsoft.UI.Windowing.TitleBarHeightOption.Tall;
      SetTitleBar(AppTitleBar);
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
          System.Diagnostics.Debug.WriteLine("Picked: " + folder.Path);
          
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